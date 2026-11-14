#!/bin/sh
# SoftEther VPN Helper Script for OpenWrt
# Handles vpncmd integration, virtual NIC, account provisioning, routing & status queries.

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

CONFIG_FILE="/etc/config/softether_client"
SE_DIR="/usr/libexec/softether"
VPNCMD="$SE_DIR/vpncmd"
RUN_DIR="/var/run/softether"
STATE_FILE="$RUN_DIR/state.json"
PID_FILE="$RUN_DIR/vpnclient.pid"
ROUTE_FILE="$RUN_DIR/routes.info"
DHCP_PID_FILE="$RUN_DIR/udhcpc.pid"

mkdir -p "$RUN_DIR"
cd "$SE_DIR" 2>/dev/null || true

log() {
	logger -t "softether-helper" "$1"
	echo "[softether-helper] $1"
}

vpncmd_call() {
	# Executes vpncmd command on local vpnclient
	export LANG="en_US.UTF-8"
	export LC_ALL="en_US.UTF-8"
	$VPNCMD localhost /client /cmd $* 2>&1
}

get_config_val() {
	local sec="$1"
	local opt="$2"
	local def="$3"
	local val
	val=$(uci -q get softether_client."$sec"."$opt")
	if [ -z "$val" ]; then
		echo "$def"
	else
		echo "$val"
	fi
}

# 1. Synchronize Virtual Network Adapter
sync_vnic() {
	local vnic
	vnic=$(get_config_val general vnic_name "vpn0")
	log "Checking virtual NIC: $vnic ..."

	local list_out
	list_out=$(vpncmd_call "NicList")

	if echo "$list_out" | grep -q -i "$vnic"; then
		log "Virtual NIC $vnic already exists."
		vpncmd_call "NicEnable $vnic" >/dev/null 2>&1
	else
		log "Creating virtual NIC: $vnic ..."
		local create_out
		create_out=$(vpncmd_call "NicCreate $vnic")
		if echo "$create_out" | grep -q -i "The command completed successfully"; then
			log "Virtual NIC $vnic created successfully."
			vpncmd_call "NicEnable $vnic" >/dev/null 2>&1
		else
			log "Failed to create virtual NIC: $create_out"
		fi
	fi
}

# 2. Synchronize Connection Account
sync_account() {
	local account_name server_host server_port hub auth_type username password
	local max_conns encrypt compress half_dup reconnect_int reconnect_cnt

	account_name=$(get_config_val main account_name "default")
	server_host=$(get_config_val main server_host "")
	server_port=$(get_config_val main server_port "443")
	hub=$(get_config_val main hub "DEFAULT")
	auth_type=$(get_config_val main auth_type "standard")
	username=$(get_config_val main username "")
	password=$(get_config_val main password "")
	vnic=$(get_config_val general vnic_name "vpn0")
	max_conns=$(get_config_val main max_connections "8")
	encrypt=$(get_config_val main encrypt "1")
	compress=$(get_config_val main compress "0")
	half_dup=$(get_config_val main half_duplex "0")
	reconnect_int=$(get_config_val main reconnect_interval "10")
	reconnect_cnt=$(get_config_val main reconnect_count "0")

	if [ -z "$server_host" ] || [ -z "$username" ]; then
		log "Server host or username is empty, skipping account sync."
		return 1
	fi

	local list_out
	list_out=$(vpncmd_call "AccountList")

	if echo "$list_out" | grep -q -i "$account_name"; then
		log "Account $account_name exists, updating parameters in-place..."
		vpncmd_call "AccountSet $account_name /SERVER:$server_host:$server_port /HUB:$hub" >/dev/null 2>&1
		vpncmd_call "AccountNicSet $account_name /NICNAME:$vnic" >/dev/null 2>&1
	else
		log "Creating account $account_name (Server: $server_host:$server_port, Hub: $hub, User: $username, NIC: $vnic)..."
		vpncmd_call "AccountCreate $account_name /SERVER:$server_host:$server_port /HUB:$hub /USERNAME:$username /NICNAME:$vnic" >/dev/null 2>&1
	fi

	if [ "$auth_type" = "standard" ] || [ "$auth_type" = "radius" ]; then
		vpncmd_call "AccountPasswordSet $account_name /PASSWORD:$password /TYPE:$auth_type" >/dev/null 2>&1
	fi

	# Detail settings: max connections, half duplex, reconnect
	local half_str="no"
	[ "$half_dup" = "1" ] && half_str="yes"
	vpncmd_call "AccountDetailSet $account_name /MAXTCP:$max_conns /INTERVAL:$reconnect_int /TTL:0 /HALF:$half_str /BRIDGE:no /MONITOR:no /NOTRACK:no /NOQOS:no" >/dev/null 2>&1

	# Encryption and compression
	local enc_str="no"
	[ "$encrypt" = "1" ] && enc_str="yes"
	vpncmd_call "AccountEncryptSet $account_name /ENCRYPT:$enc_str" >/dev/null 2>&1

	local comp_str="no"
	[ "$compress" = "1" ] && comp_str="yes"
	vpncmd_call "AccountCompressSet $account_name /COMPRESS:$comp_str" >/dev/null 2>&1

	# Disable SoftEther internal blind Layer-2 reconnection loop (controlled by OpenWrt watchdog instead)
	vpncmd_call "AccountRetrySet $account_name /NUM:0 /INTERVAL:$reconnect_int" >/dev/null 2>&1

	# Auto startup
	vpncmd_call "AccountStartupSet $account_name" >/dev/null 2>&1
	log "Account $account_name configured successfully."
}

# 3. Connect Account
connect_account() {
	export LANG="en_US.UTF-8"
	export LC_ALL="en_US.UTF-8"

	if ! pidof vpnclient >/dev/null 2>&1; then
		log "vpnclient daemon is not running. Please start the service first."
		return 1
	fi

	sync_vnic
	sync_account

	local account_name
	account_name=$(get_config_val main account_name "default")
	log "Connecting account $account_name..."
	vpncmd_call "AccountConnect $account_name" >/dev/null 2>&1

	# Wait for connection to establish and then trigger DHCP
	local count=0
	while [ $count -lt 10 ]; do
		sleep 1
		count=$((count + 1))
		local acc_out
		acc_out=$(vpncmd_call "AccountStatusGet $account_name" 2>/dev/null)
		if echo "$acc_out" | grep -i "Session Status" | grep -q -i -E "Connection Completed|Session Established"; then
			log "Session established successfully. Starting DHCP on virtual interface..."
			start_dhcp
			break
		fi
	done
}

# 4. Disconnect Account
disconnect_account() {
	local account_name vnic dev
	account_name=$(get_config_val main account_name "default")
	vnic=$(get_config_val general vnic_name "vpn0")
	dev="vpn_$vnic"

	log "Disconnecting account $account_name..."
	vpncmd_call "AccountDisconnect $account_name" >/dev/null 2>&1
	cleanup_routing
	ip -4 addr flush dev "$dev" 2>/dev/null
}

# 5. Start DHCP Client on Virtual NIC
start_dhcp() {
	local vnic dev
	vnic=$(get_config_val general vnic_name "vpn0")
	dev="vpn_$vnic"

	log "Bringing up network interface $dev..."
	ip link set dev "$dev" up 2>/dev/null

	# Kill previous udhcpc
	if [ -f "$DHCP_PID_FILE" ]; then
		kill "$(cat "$DHCP_PID_FILE")" 2>/dev/null
		rm -f "$DHCP_PID_FILE"
	fi

	log "Starting udhcpc on $dev..."
	(
		exec 1000>&- 2>/dev/null || true
		exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- 10>&- 11>&- 12>&- 13>&- 14>&- 2>/dev/null || true
		udhcpc -i "$dev" -s "$SE_DIR/udhcpc.sh" -p "$DHCP_PID_FILE" -b -t 5 -T 2 -S
	) </dev/null >/dev/null 2>&1 &
}

## 6. Apply Routing & Prevent Loop
get_chnroute_file() {
	if [ -f "/etc/softether/chnroute.txt" ]; then
		echo "/etc/softether/chnroute.txt"
	else
		echo "$SE_DIR/chnroute.txt"
	fi
}

get_chnroute_status() {
	local f
	f=$(get_chnroute_file)
	local cnt=0
	if [ -f "$f" ]; then
		cnt=$(wc -l < "$f")
	fi
	local info_file="/etc/softether/chnroute.info"
	local updated="内置规则"
	if [ -f "$info_file" ]; then
		local u
		u=$(sed -n 's/.*"updated_at": *"\([^"]*\)".*/\1/p' "$info_file")
		[ -n "$u" ] && updated="$u"
	fi
	cat <<EOF
{
	"file": "$f",
	"count": $cnt,
	"updated_at": "$updated"
}
EOF
}

update_chnroute() {
	log "Fetching latest China IP routes..."
	mkdir -p /etc/softether "$RUN_DIR"
	local tmp_raw="/tmp/chnroute_raw.txt"
	local tmp_clean="/tmp/chnroute_clean.txt"
	local success=0

	local sources="
https://cdn.jsdelivr.net/gh/misakaio/chnroutes2@master/chnroutes.txt
https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt
https://ispip.clang.cn/all_cn.txt
https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
"
	for url in $sources; do
		log "Trying source: $url ..."
		local dl_ok=0
		if which curl >/dev/null 2>&1; then
			curl -s -f -k -m 15 -o "$tmp_raw" "$url" 2>/dev/null && dl_ok=1
		elif which wget >/dev/null 2>&1; then
			wget -q --no-check-certificate -T 15 -O "$tmp_raw" "$url" 2>/dev/null && dl_ok=1
		elif which uclient-fetch >/dev/null 2>&1; then
			uclient-fetch --no-check-certificate -T 15 -O "$tmp_raw" "$url" 2>/dev/null && dl_ok=1
		fi
		if [ "$dl_ok" -eq 1 ]; then
			grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' "$tmp_raw" > "$tmp_clean"
			local cnt
			cnt=$(wc -l < "$tmp_clean")
			if [ "$cnt" -ge 3000 ]; then
				log "Successfully fetched $cnt CIDRs from $url"
				mv "$tmp_clean" /etc/softether/chnroute.txt
				[ -d "$SE_DIR" ] && cp -f /etc/softether/chnroute.txt "$SE_DIR/chnroute.txt" 2>/dev/null || true
				rm -f "$tmp_raw"
				success=1
				break
			fi
		fi
	done

	if [ "$success" -eq 1 ]; then
		local now
		now=$(date '+%Y-%m-%d %H:%M:%S')
		echo "{\"count\": $cnt, \"updated_at\": \"$now\", \"status\": \"success\"}" > /etc/softether/chnroute.info
		log "China IP routes updated: $cnt subnets at $now."

		# Hot reload routes if bypass_china is currently active
		local mode
		mode=$(uci -q get softether_client.routing.mode)
		if [ "$mode" = "bypass_china" ] && [ -f "$ROUTE_FILE" ]; then
			log "Hot-reloading China routes live in kernel..."
			local orig_gw orig_dev
			orig_gw=$(grep '^ORIG_GW=' "$ROUTE_FILE" | cut -d= -f2)
			orig_dev=$(grep '^ORIG_DEV=' "$ROUTE_FILE" | cut -d= -f2)
			if [ -n "$orig_gw" ] && [ -n "$orig_dev" ]; then
				if [ -f "$RUN_DIR/chnroute_del.txt" ]; then
					ip -batch "$RUN_DIR/chnroute_del.txt" 2>/dev/null || true
				fi
				awk -v gw="$orig_gw" -v dev="$orig_dev" '{print "route replace " $1 " via " gw " dev " dev}' /etc/softether/chnroute.txt > "$RUN_DIR/chnroute_add.txt"
				awk -v dev="$orig_dev" '{print "route del " $1 " dev " dev}' /etc/softether/chnroute.txt > "$RUN_DIR/chnroute_del.txt"
				if ! ip -batch "$RUN_DIR/chnroute_add.txt" 2>/dev/null; then
					while read -r cidr; do
						[ -n "$cidr" ] && ip route replace "$cidr" via "$orig_gw" dev "$orig_dev" 2>/dev/null || true
					done < /etc/softether/chnroute.txt
				fi
				log "China routes hot-reloaded successfully."
			fi
		fi
		echo "OK: $cnt subnets updated ($now)."
		return 0
	else
		rm -f "$tmp_raw" "$tmp_clean"
		log "Failed to update China IP routes from all sources."
		echo "ERROR: Download failed or invalid data."
		return 1
	fi
}

setup_routing() {
	local vnic dev server_host mode nat metric dns_mode
	vnic=$(get_config_val general vnic_name "vpn0")
	dev="vpn_$vnic"
	server_host=$(get_config_val main server_host "")
	mode=$(get_config_val routing mode "global")
	nat=$(get_config_val routing nat "1")
	metric=$(get_config_val routing default_metric "50")
	dns_mode=$(get_config_val routing dns_mode "vpn")

	local vpn_ip vpn_gw
	vpn_ip=$(ip -4 addr show dev "$dev" 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d ' ' -f2)
	vpn_gw=$(cat "$RUN_DIR/dhcp_gw" 2>/dev/null)

	if [ -z "$vpn_ip" ] || [ -z "$vpn_gw" ]; then
		log "VPN IP ($vpn_ip) or Gateway ($vpn_gw) not yet ready."
		return 1
	fi

	log "Setting up routes for $dev (VPN IP: $vpn_ip, Gateway: $vpn_gw, Mode: $mode)..."

	# Get original default gateway to prevent routing loop
	local orig_gw orig_dev
	orig_gw=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)
	orig_dev=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)

	if [ -z "$orig_gw" ]; then
		orig_gw=$(uci -q get network.lan.gateway || uci -q get network.wan.gateway)
	fi
	if [ -z "$orig_dev" ]; then
		orig_dev=$(uci -q get network.lan.device || uci -q get network.wan.device || echo "eth0")
	fi

	# Resolve server host IP
	local server_ip=""
	if echo "$server_host" | grep -q -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
		server_ip="$server_host"
	else
		server_ip=$(nslookup "$server_host" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
		if [ -z "$server_ip" ]; then
			server_ip=$(ping -c 1 "$server_host" 2>/dev/null | grep -o -E '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()' | head -n1)
		fi
	fi

	echo "ORIG_GW=$orig_gw" > "$ROUTE_FILE"
	echo "ORIG_DEV=$orig_dev" >> "$ROUTE_FILE"
	echo "SERVER_IP=$server_ip" >> "$ROUTE_FILE"
	echo "VPN_DEV=$dev" >> "$ROUTE_FILE"
	echo "VPN_GW=$vpn_gw" >> "$ROUTE_FILE"
	echo "MODE=$mode" >> "$ROUTE_FILE"

	# 1. Prevent VPN routing loop: host route to VPN server via original WAN gateway
	if [ -n "$server_ip" ] && [ -n "$orig_gw" ] && [ -n "$orig_dev" ]; then
		log "Adding anti-loop host route: $server_ip/32 via $orig_gw dev $orig_dev"
		ip route replace "$server_ip/32" via "$orig_gw" dev "$orig_dev"
	fi

	# 2. Configure routes according to mode
	if [ "$mode" = "global" ]; then
		log "Applying Global Route (0.0.0.0/1 & 128.0.0.0/1 via $vpn_gw)..."
		ip route replace 0.0.0.0/1 via "$vpn_gw" dev "$dev" metric "$metric"
		ip route replace 128.0.0.0/1 via "$vpn_gw" dev "$dev" metric "$metric"
	elif [ "$mode" = "bypass_china" ]; then
		log "Applying Bypass China Mode (Domestic Direct via $orig_gw, Foreign via $vpn_gw)..."
		ip route replace 0.0.0.0/1 via "$vpn_gw" dev "$dev" metric "$metric"
		ip route replace 128.0.0.0/1 via "$vpn_gw" dev "$dev" metric "$metric"

		local chn_file
		chn_file=$(get_chnroute_file)
		if [ -f "$chn_file" ] && [ -n "$orig_gw" ] && [ -n "$orig_dev" ]; then
			log "Injecting China IP routes via $orig_gw dev $orig_dev (source: $chn_file)..."
			awk -v gw="$orig_gw" -v dev="$orig_dev" '{print "route replace " $1 " via " gw " dev " dev}' "$chn_file" > "$RUN_DIR/chnroute_add.txt"
			awk -v dev="$orig_dev" '{print "route del " $1 " dev " dev}' "$chn_file" > "$RUN_DIR/chnroute_del.txt"
			if ip -batch "$RUN_DIR/chnroute_add.txt" 2>/dev/null; then
				log "China routes applied successfully via ip -batch."
			else
				log "ip -batch not supported, injecting routes via fallback loop..."
				while read -r cidr; do
					[ -n "$cidr" ] && ip route replace "$cidr" via "$orig_gw" dev "$orig_dev" 2>/dev/null || true
				done < "$chn_file"
				log "China routes applied successfully via fallback loop."
			fi
		else
			log "Warning: chnroute.txt not found or WAN gateway missing, fallback to global."
		fi
	elif [ "$mode" = "custom" ]; then
		log "Applying Custom Subnet routes via $vpn_gw..."
		local subnets
		subnets=$(uci -q get softether_client.routing.subnet)
		for s in $subnets; do
			log "Adding route for subnet $s via $vpn_gw"
			ip route replace "$s" via "$vpn_gw" dev "$dev"
		done
	fi

	# 3. NAT Masquerade, MSS Clamping & Firewall Zone
	if [ "$nat" = "1" ]; then
		log "Configuring firewall forwarding and NAT for $dev..."

		# Ensure UCI firewall zone exists
		if ! uci -q get firewall.softether_zone >/dev/null 2>&1; then
			uci set firewall.softether_zone=zone
			uci set firewall.softether_zone.name='softether'
			uci set firewall.softether_zone.input='ACCEPT'
			uci set firewall.softether_zone.output='ACCEPT'
			uci set firewall.softether_zone.forward='ACCEPT'
			uci set firewall.softether_zone.masq='1'
			uci set firewall.softether_zone.mtu_fix='1'
			uci add_list firewall.softether_zone.device="$dev"

			uci set firewall.softether_forward=forwarding
			uci set firewall.softether_forward.src='lan'
			uci set firewall.softether_forward.dest='softether'
			uci commit firewall
			/etc/init.d/firewall reload >/dev/null 2>&1 || true
		else
			local cur_devices
			cur_devices=$(uci -q get firewall.softether_zone.device)
			if ! echo "$cur_devices" | grep -q "$dev"; then
				uci add_list firewall.softether_zone.device="$dev"
				uci commit firewall
				/etc/init.d/firewall reload >/dev/null 2>&1 || true
			fi
		fi

		# nftables native fallback
		if which nft >/dev/null 2>&1; then
			nft add rule inet fw4 srcnat oifname "$dev" counter masquerade 2>/dev/null || true
		fi

		# iptables fallback
		if which iptables >/dev/null 2>&1; then
			iptables -t nat -C POSTROUTING -o "$dev" -j MASQUERADE 2>/dev/null || \
				iptables -t nat -A POSTROUTING -o "$dev" -j MASQUERADE 2>/dev/null || true
			iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$dev" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
				iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$dev" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
		fi
	fi

	# 4. Clean DNS Injection for Google and Foreign Sites
	if [ "$dns_mode" = "vpn" ] || [ "$dns_mode" = "custom" ]; then
		local target_dns=""
		if [ "$dns_mode" = "vpn" ]; then
			target_dns=$(cat "$RUN_DIR/dhcp_dns" 2>/dev/null | awk '{print $1}')
			[ -z "$target_dns" ] && target_dns="8.8.8.8"
		else
			target_dns=$(uci -q get softether_client.routing.custom_dns)
			[ -z "$target_dns" ] && target_dns="8.8.8.8"
		fi

		log "Applying clean DNS ($target_dns, 1.1.1.1) to dnsmasq..."
		echo "TARGET_DNS=$target_dns" >> "$ROUTE_FILE"
		local orig_noresolv
		orig_noresolv=$(uci -q get dhcp.@dnsmasq[0].noresolv || echo "0")
		echo "ORIG_NORESOLV=$orig_noresolv" >> "$ROUTE_FILE"

		uci -q del_list dhcp.@dnsmasq[0].server="$target_dns" 2>/dev/null || true
		uci -q del_list dhcp.@dnsmasq[0].server="1.1.1.1" 2>/dev/null || true
		uci add_list dhcp.@dnsmasq[0].server="$target_dns"
		uci set dhcp.@dnsmasq[0].noresolv='1'
		# Ensure dnsmasq loads /tmp/dnsmasq.d for dynamic rules
		mkdir -p /tmp/dnsmasq.d
		local confdirs
		confdirs=$(uci -q get dhcp.@dnsmasq[0].confdir)
		if ! echo "$confdirs" | grep -q "/tmp/dnsmasq.d"; then
			uci add_list dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
		fi

		# In bypass_china mode, add Smart Domestic DNS rules so domestic CDNs (ip138, aliyun, qq, etc.) resolve to fast domestic IPs
		if [ "$mode" = "bypass_china" ]; then
			log "Writing domestic domain DNS split rules to /tmp/dnsmasq.d/softether_domestic.conf..."
			cat << 'DOM_EOF' > /tmp/dnsmasq.d/softether_domestic.conf
server=/cn/223.5.5.5
server=/ip138.com/223.5.5.5
server=/baidu.com/223.5.5.5
server=/qq.com/223.5.5.5
server=/tencent.com/223.5.5.5
server=/taobao.com/223.5.5.5
server=/tmall.com/223.5.5.5
server=/alipay.com/223.5.5.5
server=/aliyun.com/223.5.5.5
server=/alicdn.com/223.5.5.5
server=/jd.com/223.5.5.5
server=/bilibili.com/223.5.5.5
server=/hdslb.com/223.5.5.5
server=/163.com/223.5.5.5
server=/126.com/223.5.5.5
server=/zhihu.com/223.5.5.5
server=/douyin.com/223.5.5.5
server=/bytedance.com/223.5.5.5
server=/weibo.com/223.5.5.5
server=/bdimg.com/223.5.5.5
server=/lxdns.com/223.5.5.5
server=/wswebpic.com/223.5.5.5
DOM_EOF
		fi

		uci commit dhcp
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	fi

	log "Route configuration completed."
}

# 7. Cleanup Routes
cleanup_routing() {
	if [ ! -f "$ROUTE_FILE" ]; then
		return 0
	fi

	log "Cleaning up routes..."
	. "$ROUTE_FILE" 2>/dev/null

	if [ "$MODE" = "global" ] && [ -n "$VPN_DEV" ]; then
		ip route del 0.0.0.0/1 dev "$VPN_DEV" 2>/dev/null
		ip route del 128.0.0.0/1 dev "$VPN_DEV" 2>/dev/null
	elif [ "$MODE" = "bypass_china" ]; then
		[ -n "$VPN_DEV" ] && ip route del 0.0.0.0/1 dev "$VPN_DEV" 2>/dev/null
		[ -n "$VPN_DEV" ] && ip route del 128.0.0.0/1 dev "$VPN_DEV" 2>/dev/null
		if [ -f "$RUN_DIR/chnroute_del.txt" ]; then
			log "Removing China bypass routes..."
			if ! ip -batch "$RUN_DIR/chnroute_del.txt" 2>/dev/null; then
				local chn_file
				chn_file=$(get_chnroute_file)
				if [ -f "$chn_file" ] && [ -n "$ORIG_DEV" ]; then
					while read -r cidr; do
						[ -n "$cidr" ] && ip route del "$cidr" dev "$ORIG_DEV" 2>/dev/null || true
					done < "$chn_file"
				fi
			fi
			rm -f "$RUN_DIR/chnroute_add.txt" "$RUN_DIR/chnroute_del.txt"
		fi
	elif [ "$MODE" = "custom" ] && [ -n "$VPN_DEV" ]; then
		local subnets
		subnets=$(uci -q get softether_client.routing.subnet)
		for s in $subnets; do
			ip route del "$s" dev "$VPN_DEV" 2>/dev/null
		done
	fi

	if [ -n "$SERVER_IP" ]; then
		ip route del "$SERVER_IP/32" 2>/dev/null
	fi

	if [ -n "$VPN_DEV" ]; then
		iptables -t nat -D POSTROUTING -o "$VPN_DEV" -j MASQUERADE 2>/dev/null || true
		iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$VPN_DEV" -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
	fi

	rm -f /tmp/dnsmasq.d/softether_domestic.conf
	if [ -n "$TARGET_DNS" ]; then
		log "Reverting DNS settings in dnsmasq..."
		uci -q del_list dhcp.@dnsmasq[0].server="$TARGET_DNS" 2>/dev/null || true
		uci -q del_list dhcp.@dnsmasq[0].server="1.1.1.1" 2>/dev/null || true
		if [ -n "$ORIG_NORESOLV" ]; then
			uci set dhcp.@dnsmasq[0].noresolv="$ORIG_NORESOLV"
		else
			uci -q delete dhcp.@dnsmasq[0].noresolv
		fi
		uci commit dhcp
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	fi

	if [ -f "$DHCP_PID_FILE" ]; then
		kill "$(cat "$DHCP_PID_FILE")" 2>/dev/null
		rm -f "$DHCP_PID_FILE"
	fi

	rm -f "$ROUTE_FILE" "$RUN_DIR/dhcp_gw" "$RUN_DIR/dhcp_dns"
	log "Routes cleaned up."
}

# 8. Query Status and Output JSON for LuCI
get_status_json() {
	export LANG="en_US.UTF-8"
	export LC_ALL="en_US.UTF-8"

	local running="false"
	local pid=""
	if pidof vpnclient >/dev/null 2>&1; then
		running="true"
		pid=$(pidof vpnclient | awk '{print $1}')
	fi

	local vnic dev vnic_up="false" ip_addr=""
	vnic=$(get_config_val general vnic_name "vpn0")
	dev="vpn_$vnic"

	if [ -d "/sys/class/net/$dev" ]; then
		vnic_up="true"
		ip_addr=$(ip -4 addr show dev "$dev" 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d ' ' -f2 | head -n1)
	fi

	local account_name conn_status="Disconnected" server_ip="" session_name=""
	account_name=$(get_config_val main account_name "default")

	local acc_out
	acc_out=$(vpncmd_call "AccountStatusGet $account_name" 2>/dev/null)

	if echo "$acc_out" | grep -i "Session Status" | grep -q -i -E "Connection Completed|Session Established"; then
		conn_status="Connected"
	elif echo "$acc_out" | grep -i "Session Status" | grep -q -i "Connecting"; then
		conn_status="Connecting"
	elif echo "$acc_out" | grep -i "Session Status" | grep -q -i "Retry"; then
		conn_status="Retrying"
	else
		conn_status="Disconnected"
	fi

	if [ "$conn_status" = "Connected" ]; then
		server_ip=$(echo "$acc_out" | grep -E -i "Server IP Address|Server Name" | head -n1 | awk -F'|' '{print $2}' | tr -d ' \r\n')
		session_name=$(echo "$acc_out" | grep -i "Session Name" | head -n1 | awk -F'|' '{print $2}' | tr -d ' \r\n')
	fi

	local rx_bytes="0" tx_bytes="0"
	if [ -f "/sys/class/net/$dev/statistics/rx_bytes" ]; then
		rx_bytes=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null)
		tx_bytes=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null)
	fi
	[ -z "$rx_bytes" ] && rx_bytes="0"
	[ -z "$tx_bytes" ] && tx_bytes="0"

	cat <<EOF
{
	"running": $running,
	"pid": "$pid",
	"vnic": "$vnic",
	"device": "$dev",
	"device_up": $vnic_up,
	"ip_address": "$ip_addr",
	"connection_status": "$conn_status",
	"server_ip": "$server_ip",
	"session_name": "$session_name",
	"rx_bytes": $rx_bytes,
	"tx_bytes": $tx_bytes
}
EOF
}

case "$1" in
	sync_vnic)
		sync_vnic
		;;
	sync_account)
		sync_account
		;;
	connect)
		connect_account
		;;
	disconnect)
		disconnect_account
		;;
	start_dhcp)
		start_dhcp
		;;
	setup_routing)
		setup_routing
		;;
	cleanup_routing)
		cleanup_routing
		;;
	status)
		get_status_json
		;;
	update_chnroute)
		update_chnroute
		;;
	chnroute_status)
		get_chnroute_status
		;;
	cmd)
		shift
		vpncmd_call "$*"
		;;
	*)
		echo "Usage: $0 {sync_vnic|sync_account|connect|disconnect|start_dhcp|setup_routing|cleanup_routing|status|update_chnroute|chnroute_status|cmd <args>}"
		exit 1
		;;
esac
