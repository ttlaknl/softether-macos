#!/bin/sh
# udhcpc script for SoftEther VPN client virtual interface
[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1

RUN_DIR="/var/run/softether"
mkdir -p "$RUN_DIR"

case "$1" in
	deconfig)
		ip -4 addr flush dev "$interface" 2>/dev/null
		;;
	renew|bound)
		# Set IP address on interface
		ip -4 addr replace "$ip/${subnet:-255.255.255.0}" broadcast "${broadcast:-+}" dev "$interface"

		if [ -n "$router" ]; then
			# Save DHCP gateway (use the first router if multiple)
			first_router=$(echo "$router" | awk '{print $1}')
			echo "$first_router" > "$RUN_DIR/dhcp_gw"
		fi

		if [ -n "$dns" ]; then
			echo "$dns" > "$RUN_DIR/dhcp_dns"
		fi

		# Trigger routing setup
		if [ -x "/usr/libexec/softether/softether-helper.sh" ]; then
			/usr/libexec/softether/softether-helper.sh setup_routing
		fi
		;;
esac

exit 0
