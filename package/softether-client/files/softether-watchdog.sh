#!/bin/sh
# SoftEther Watchdog Script for OpenWrt
# Monitors daemon, tunnel connectivity, and handles auto-reconnection

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

HELPER="/usr/libexec/softether/softether-helper.sh"
FAIL_COUNT_FILE="/var/run/softether/watchdog_fail_count"
EMPTY_IP_COUNT_FILE="/var/run/softether/watchdog_empty_ip_count"
LAST_SESSION_FILE="/var/run/softether/watchdog_last_session"

enabled=$(uci -q get softether_client.general.enabled)
[ "$enabled" != "1" ] && exit 0

watchdog=$(uci -q get softether_client.general.watchdog)
[ "$watchdog" = "0" ] && exit 0

ping_host=$(uci -q get softether_client.general.ping_host)
[ -z "$ping_host" ] && ping_host="8.8.8.8"

vnic=$(uci -q get softether_client.general.vnic_name)
[ -z "$vnic" ] && vnic="vpn0"
dev="vpn_$vnic"

# 1. Check if daemon is running
if ! pidof vpnclient >/dev/null 2>&1; then
	logger -t "softether-watchdog" "vpnclient daemon died, restarting service..."
	/etc/init.d/softether-client restart
	exit 0
fi

# 2. Check if device exists
if [ ! -d "/sys/class/net/$dev" ]; then
	logger -t "softether-watchdog" "Device $dev not found, re-syncing virtual NIC..."
	$HELPER sync_vnic
fi

# 3. Check account status
acc_status=$($HELPER status | grep '"connection_status"' | cut -d '"' -f4)

if [ "$acc_status" = "Disconnected" ]; then
	logger -t "softether-watchdog" "Tunnel disconnected, reconnecting..."
	$HELPER connect
	exit 0
fi

if [ "$acc_status" = "Connected" ]; then
	# Check IP assignment
	ip_addr=$(ip -4 addr show dev "$dev" 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d ' ' -f2)
	if [ -z "$ip_addr" ]; then
		empty_count=$(cat "$EMPTY_IP_COUNT_FILE" 2>/dev/null || echo 0)
		empty_count=$((empty_count + 1))
		echo "$empty_count" > "$EMPTY_IP_COUNT_FILE"
		logger -t "softether-watchdog" "Connected but no IP assigned to $dev ($empty_count/2), requesting DHCP..."
		$HELPER start_dhcp

		if [ "$empty_count" -ge 2 ]; then
			logger -t "softether-watchdog" "Tunnel in stale state (Connected with no IP for 2 checks). Performing full service restart to auto self-heal..."
			rm -f "$EMPTY_IP_COUNT_FILE" "$FAIL_COUNT_FILE"
			/etc/init.d/softether-client restart
			exit 0
		fi
		exit 0
	else
		rm -f "$EMPTY_IP_COUNT_FILE"
	fi

	# Detect session reconnects / flapping
	cur_session=$($HELPER status | grep '"session_name"' | cut -d '"' -f4)
	last_session=$(cat "$LAST_SESSION_FILE" 2>/dev/null || echo "")
	if [ -n "$cur_session" ] && [ -n "$last_session" ] && [ "$cur_session" != "$last_session" ]; then
		logger -t "softether-watchdog" "Session changed from $last_session to $cur_session. Refreshing DHCP lease and routing..."
		$HELPER start_dhcp
	fi
	[ -n "$cur_session" ] && echo "$cur_session" > "$LAST_SESSION_FILE"

	# Ping check through dev
	if ! ping -I "$dev" -c 2 -W 3 "$ping_host" >/dev/null 2>&1; then
		fail_count=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
		fail_count=$((fail_count + 1))
		echo "$fail_count" > "$FAIL_COUNT_FILE"
		logger -t "softether-watchdog" "Ping to $ping_host via $dev failed ($fail_count/3)"

		if [ "$fail_count" -ge 3 ]; then
			logger -t "softether-watchdog" "Tunnel connectivity failed 3 times. Performing full service restart to auto self-heal..."
			rm -f "$FAIL_COUNT_FILE" "$EMPTY_IP_COUNT_FILE"
			/etc/init.d/softether-client restart
			exit 0
		fi
	else
		rm -f "$FAIL_COUNT_FILE"
	fi
fi

exit 0
