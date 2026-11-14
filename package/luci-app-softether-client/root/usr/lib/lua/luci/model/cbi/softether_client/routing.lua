local m, s, o

m = Map("softether_client", translate("SoftEther VPN - Routing Policy"),
	translate("Configure routing table modification and traffic steering rules."))

s = m:section(NamedSection, "routing", "routing", translate("Routing & Forwarding"))
s.anonymous = true

o = s:option(ListValue, "mode", translate("Routing Mode"))
o:value("bypass_china", translate("Bypass Mainland China (Domestic Direct, Foreign via VPN)"))
o:value("global", translate("Global VPN (All Traffic)"))
o:value("custom", translate("Split Tunneling (Subnets)"))
o:value("none", translate("Interface Only"))
o.default = "bypass_china"

o = s:option(DynamicList, "subnet", translate("Split Tunneling Subnets"),
	translate("CIDR subnets (e.g. 10.0.0.0/8, 192.168.0.0/16)."))
o:depends("mode", "custom")
o.datatype = "cidr4"

o = s:option(Flag, "nat", translate("Enable NAT Masquerade"),
	translate("Forward LAN packets via VPN interface."))
o.default = "1"

o = s:option(Value, "default_metric", translate("Route Metric"))
o.default = "50"
o.datatype = "uinteger"

return m
