'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('softether_client', 'SoftEther VPN 客户端参数设置',
			'配置客户端后台服务运行状态、远程 VPN 服务器连接凭证以及并发多流性能加速。');

		// 1. 基本设置
		s = m.section(form.NamedSection, 'general', 'global', '基本服务设置');
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', '启用客户端服务',
			'开机自动启动并在配置保存后自动拉起 SoftEther VPN 守护进程。');
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.Value, 'vnic_name', '虚拟网卡适配器名称',
			'SoftEther 内部虚拟网卡名称（默认为 vpn0，对应的 Linux 系统接口为 vpn_vpn0）。');
		o.default = 'vpn0';
		o.rmempty = false;

		o = s.option(form.Flag, 'watchdog', '断线看门狗保活',
			'自动定期探测 VPN 隧道连通性，在网络异常或进程挂死时自动重启并重新拨号。');
		o.default = '1';

		o = s.option(form.Value, 'ping_host', '看门狗探测目标 IP',
			'用于测试 VPN 连通性的公网或内网探测地址（如 223.5.5.5 或 119.29.29.29）。');
		o.default = '223.5.5.5';
		o.datatype = 'ip4addr';

		// 2. 远程连接账户
		s = m.section(form.NamedSection, 'main', 'account', 'VPN 服务器与认证账户');
		s.anonymous = true;

		o = s.option(form.Value, 'account_name', '连接账户名称');
		o.default = 'default';
		o.rmempty = false;

		o = s.option(form.Value, 'server_host', 'VPN 服务器地址 / 域名',
			'远程 SoftEther VPN 服务端的主机域名或公网 IP 地址。');
		o.rmempty = false;

		o = s.option(form.Value, 'server_port', '服务器连接端口',
			'SoftEther 监听端口（常用端口：443、992、1194、5555）。');
		o.default = '443';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.Value, 'hub', '虚拟 Hub 名称',
			'远程服务端配置的 Virtual Hub 名称（默认通常为 DEFAULT 或 VPN）。');
		o.default = 'DEFAULT';
		o.rmempty = false;

		o = s.option(form.ListValue, 'auth_type', '身份验证方式');
		o.value('standard', '标准密码认证 (Standard Password)');
		o.value('radius', 'RADIUS / 域认证 (NT Domain)');
		o.default = 'standard';

		o = s.option(form.Value, 'username', '登录用户名');
		o.rmempty = false;

		o = s.option(form.Value, 'password', '登录密码');
		o.password = true;
		o.rmempty = false;

		// 3. 性能优化与并发加速
		o = s.option(form.ListValue, 'max_connections', '并发 TCP 连接数 (Multi-TCP 并发加速)',
			'SoftEther 独家核心加速特性：建立多条并发 TCP 隧道突破单流限速与丢包瓶颈，在跨国与高延迟网络下效果显著。');
		o.value('1', '1 条流 (标准单流模式)');
		o.value('2', '2 条流');
		o.value('4', '4 条流');
		o.value('8', '8 条流 (官方推荐加速)');
		o.value('16', '16 条流 (高吞吐强力优化)');
		o.value('32', '32 条流 (极限并发加速)');
		o.default = '8';

		o = s.option(form.Flag, 'encrypt', 'SSL 数据传输加密',
			'使用 AES-128/256 对全量传输数据进行 SSL 加密。在可信内网中可关闭以获得更高 CPU 转发性能。');
		o.default = '1';

		o = s.option(form.Flag, 'compress', '数据包硬件压缩',
			'在传输前对数据包进行压缩，适合低带宽或计费流量连接。');
		o.default = '0';

		o = s.option(form.Flag, 'half_duplex', '半双工通信模式',
			'在极度严格的防火墙或特定 NAT 环境下使用，通常保持关闭。');
		o.default = '0';

		o = s.option(form.Value, 'reconnect_interval', '断线重试间隔 (秒)');
		o.default = '10';
		o.datatype = 'uinteger';

		return m.render();
	}
});
