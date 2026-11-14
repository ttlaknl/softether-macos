module("luci.controller.softether_client", package.seeall)

function index()
	-- API endpoints for AJAX action calls
	entry({"admin", "vpn", "softether_api", "action"}, call("action_op")).leaf = true
end

function action_op()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local op = http.formvalue("op")
	local ret = 1

	if op == "connect" then
		ret = sys.call("/usr/libexec/softether/softether-helper.sh connect >/dev/null 2>&1")
	elseif op == "disconnect" then
		ret = sys.call("/usr/libexec/softether/softether-helper.sh disconnect >/dev/null 2>&1")
	elseif op == "restart" then
		ret = sys.call("/etc/init.d/softether-client restart >/dev/null 2>&1")
	end

	http.prepare_content("application/json")
	http.write_json({ code = ret })
end
