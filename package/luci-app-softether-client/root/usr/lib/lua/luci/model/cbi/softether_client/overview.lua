local m, s, o
local sys = require "luci.sys"

m = Map("softether_client", translate("SoftEther VPN Client - Overview"),
	translate("Manage SoftEther VPN daemon service and global options."))

s = m:section(NamedSection, "general", "global", translate("Service Control"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable Service"))
o.rmempty = false
o.default = "0"

o = s:option(Value, "vnic_name", translate("Virtual Adapter Name"),
	translate("Device name inside SoftEther. Linux interface will be vpn_<name>."))
o.default = "vpn0"
o.rmempty = false

o = s:option(Flag, "watchdog", translate("Connection Watchdog"),
	translate("Auto-reconnect if ping checks fail."))
o.default = "1"

o = s:option(Value, "ping_host", translate("Ping Target"),
	translate("Target host for connectivity tests."))
o.default = "223.5.5.5"

return m
