'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return Promise.all([
			fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['chnroute_status']).catch(function() { return '{}'; })
		]);
	},

	render: function(data) {
		var chnStatus = {};
		try {
			chnStatus = JSON.parse(data[0] || '{}');
		} catch (e) {
			chnStatus = {};
		}

		var m, s, o;

		m = new form.Map('softether_client', '路由策略与流量转发配置',
			'灵活配置 VPN 隧道的路由规则、国内直连分流、指定内网网段分流以及防火墙 NAT 自动伪装。');

		s = m.section(form.NamedSection, 'routing', 'routing', '流量转发与路由策略');
		s.anonymous = true;

		o = s.option(form.ListValue, 'mode', '路由分流模式');
		o.value('bypass_china', '绕过大陆模式 (国内直连不耗流量，国外走 VPN - 推荐)');
		o.value('global', '全局 VPN 模式 (全部上网流量均经由 VPN 隧道转发)');
		o.value('custom', '规则分流模式 (仅将下方指定目标网段走 VPN，其余直连)');
		o.value('none', '仅接口模式 (不自动修改系统路由，由用户或 MWAN3 手动管理)');
		o.default = 'bypass_china';

		// Bypass China Details
		o = s.option(form.DummyValue, '_chn_status', '国内 IP 路由表状态');
		o.depends('mode', 'bypass_china');
		o.rawhtml = true;
		o.cfgvalue = function() {
			var cnt = chnStatus.count || 0;
			var updated = chnStatus.updated_at || '内置规则';
			return '<span>已生效 <strong>' + cnt + '</strong> 条国内网段 CIDR (最近更新: <strong>' + updated + '</strong>)</span>';
		};

		o = s.option(form.Button, '_btn_update_chn', '在线更新国内 IP 库');
		o.depends('mode', 'bypass_china');
		o.inputtitle = '立即从权威源更新国内 IP 路由表';
		o.inputstyle = 'apply';
		o.onclick = function(ev) {
			var btn = ev.target;
			btn.disabled = true;
			ui.showIndicator('chn-update', '正在从权威镜像下载并热重载国内 IP 路由表 (耗时约 2 秒)...');
			return fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['update_chnroute']).then(function(res) {
				ui.hideIndicator('chn-update');
				btn.disabled = false;
				if (res && res.indexOf('OK:') !== -1) {
					ui.addNotification(null, E('p', '国内 IP 路由表已成功在线更新并热重载至 Linux 内核！' + res), 'info');
					setTimeout(function() { window.location.reload(); }, 1500);
				} else {
					ui.addNotification(null, E('p', '更新失败：' + (res || '下载失败或网络超时')), 'error');
				}
			}).catch(function(err) {
				ui.hideIndicator('chn-update');
				btn.disabled = false;
				ui.addNotification(null, E('p', '执行出错：' + (err.message || err)), 'error');
			});
		};

		o = s.option(form.ListValue, 'auto_update_chnroute', '自动定时更新国内 IP 库');
		o.depends('mode', 'bypass_china');
		o.value('0', '禁用自动更新');
		o.value('weekly', '每周一凌晨 04:00 自动静默更新 (推荐)');
		o.value('monthly', '每月 1 日凌晨 04:00 自动静默更新');
		o.default = 'weekly';

		o = s.option(form.DynamicList, 'subnet', '分流目标内网网段',
			'需要经由 VPN 隧道访问的目标 CIDR 网段列表（例如 10.0.0.0/8、172.16.0.0/12、192.168.0.0/16）。');
		o.depends('mode', 'custom');
		o.datatype = 'cidr4';

		o = s.option(form.Flag, 'nat', '启用 NAT 地址伪装 (MASQUERADE)',
			'自动向防火墙注入 NAT 规则，允许路由器局域网（LAN）所有设备无感免配置透明使用 VPN 隧道。');
		o.default = '1';

		o = s.option(form.Value, 'default_metric', '默认路由跃点数 (Metric)',
			'VPN 默认路由的优先级跃点数（数值越小优先级越高，默认为 50）。');
		o.default = '50';
		o.datatype = 'uinteger';

		o = s.option(form.ListValue, 'dns_mode', 'DNS 解析策略');
		o.value('keep', '保持路由器现有 WAN DNS (防止国内域名解析被劫持或变慢)');
		o.value('vpn', '使用 VPN DHCP 自动下发的 DNS 服务器');
		o.value('custom', '自定义指定专用 DNS 服务器');
		o.default = 'keep';

		o = s.option(form.DynamicList, 'custom_dns', '自定义 DNS 服务器列表',
			'连接成功后指定的 DNS IP 地址列表（例如 223.5.5.5、119.29.29.29、1.1.1.1）。');
		o.depends('dns_mode', 'custom');
		o.datatype = 'ip4addr';

		return m.render();
	}
});
