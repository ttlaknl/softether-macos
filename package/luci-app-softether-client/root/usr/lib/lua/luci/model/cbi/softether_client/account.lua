local m, s, o

m = Map("softether_client", translate("SoftEther VPN - Account Settings"),
	translate("Configure remote SoftEther VPN server credentials and connection acceleration parameters."))

s = m:section(NamedSection, "main", "account", translate("Server Account"))
s.anonymous = true

o = s:option(Value, "server_host", translate("VPN Server Address"))
o.rmempty = false

o = s:option(Value, "server_port", translate("VPN Server Port"))
o.default = "443"
o.datatype = "port"

o = s:option(Value, "hub", translate("Virtual Hub Name"))
o.default = "DEFAULT"
o.rmempty = false

o = s:option(ListValue, "auth_type", translate("Authentication Method"))
o:value("standard", translate("Standard Password"))
o:value("radius", translate("RADIUS / External"))
o.default = "standard"

o = s:option(Value, "username", translate("Username"))
o.rmempty = false

o = s:option(Value, "password", translate("Password"))
o.password = true
o.rmempty = false

o = s:option(ListValue, "max_connections", translate("Concurrent TCP Streams"),
	translate("SoftEther multi-stream TCP connection acceleration."))
o:value("1", "1 Stream")
o:value("2", "2 Streams")
o:value("4", "4 Streams")
o:value("8", "8 Streams (Recommended)")
o:value("16", "16 Streams")
o:value("32", "32 Streams")
o.default = "8"

o = s:option(Flag, "encrypt", translate("SSL Encryption"))
o.default = "1"

o = s:option(Flag, "compress", translate("Data Compression"))
o.default = "0"

return m
