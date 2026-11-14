'use strict';
'require view';
'require fs';
'require ui';
'require poll';

return view.extend({
	load: function() {
		return Promise.all([
			fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['status']).catch(function() { return '{}'; })
		]);
	},

	formatBytes: function(bytes) {
		bytes = parseInt(bytes) || 0;
		if (bytes === 0) return '0 B';
		var k = 1024;
		var sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
		var i = Math.floor(Math.log(bytes) / Math.log(k));
		return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
	},

	render: function(data) {
		var self = this;
		var status = {};
		try {
			status = JSON.parse(data[0] || '{}');
		} catch (e) {
			status = {};
		}

		var m = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'SoftEther VPN 客户端 - 运行状态总览'),
			E('div', { 'class': 'cbi-map-descr' }, '实时监控 SoftEther VPN 客户端守护进程、隧道连接状态、虚拟网络接口及收发网络流量。')
		]);

		var statusTable = E('table', { 'class': 'table', 'id': 'softether_status_table' }, [
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'style': 'width: 30%' }, '客户端守护进程：'),
				E('td', { 'class': 'td left', 'id': 'val_daemon' }, status.running ?
					E('span', { 'class': 'badge badge-success' }, '运行中 (PID: ' + (status.pid || 'N/A') + ')') :
					E('span', { 'class': 'badge badge-danger' }, '已停止'))
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, '隧道连接状态：'),
				E('td', { 'class': 'td left', 'id': 'val_conn_status' },
					status.connection_status === 'Connected' ?
						E('span', { 'class': 'badge badge-success' }, '已连接') :
						(status.connection_status === 'Connecting' ?
							E('span', { 'class': 'badge badge-warning' }, '正在连接...') :
							(status.connection_status === 'Retrying' ?
								E('span', { 'class': 'badge badge-warning' }, '正在重试连接...') :
								E('span', { 'class': 'badge badge-secondary' }, '已断开'))))
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, '虚拟网络接口：'),
				E('td', { 'class': 'td left', 'id': 'val_device' },
					(status.device || 'vpn_vpn0') + (status.device_up ? ' (已启用/UP)' : ' (未启用/DOWN)'))
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, '分配的 VPN IP 地址：'),
				E('td', { 'class': 'td left', 'id': 'val_ip' },
					status.ip_address ? E('strong', {}, status.ip_address) : '尚未分配 IP 地址')
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, '远程服务器 IP 地址：'),
				E('td', { 'class': 'td left', 'id': 'val_server_ip' }, status.server_ip || '暂无')
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, '当前活动会话：'),
				E('td', { 'class': 'td left', 'id': 'val_session' }, status.session_name || '无活动会话')
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, '实时网络收发流量：'),
				E('td', { 'class': 'td left', 'id': 'val_traffic' },
					'接收 (RX): ' + self.formatBytes(status.rx_bytes) + ' | 发送 (TX): ' + self.formatBytes(status.tx_bytes))
			])
		]);

		var isConnected = (status.connection_status === 'Connected');

		var btnConnect = E('button', {
			'id': 'btn_connect',
			'class': 'btn cbi-button-action',
			'style': 'margin-right: 10px;' + (isConnected ? 'display: none;' : ''),
			'click': function(ev) {
				ev.target.disabled = true;
				ui.showIndicator('se-act', '正在发起连接...');
				var p = status.running ?
					fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['connect']) :
					fs.exec_direct('/etc/init.d/softether-client', ['start']);
				p.then(function() {
					ui.hideIndicator('se-act');
					ev.target.disabled = false;
				}).catch(function() {
					ui.hideIndicator('se-act');
					ev.target.disabled = false;
				});
			}
		}, '连接 VPN');

		var btnDisconnect = E('button', {
			'id': 'btn_disconnect',
			'class': 'btn cbi-button-reset',
			'style': 'margin-right: 10px;' + (isConnected ? '' : 'display: none;'),
			'click': function(ev) {
				ev.target.disabled = true;
				ui.showIndicator('se-act', '正在断开连接...');
				fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['disconnect']).then(function() {
					ui.hideIndicator('se-act');
					ev.target.disabled = false;
				});
			}
		}, '断开连接');

		var btnRestart = E('button', {
			'class': 'btn cbi-button-apply',
			'click': function(ev) {
				ev.target.disabled = true;
				ui.showIndicator('se-act', '正在重启后台服务...');
				fs.exec_direct('/etc/init.d/softether-client', ['restart']).then(function() {
					ui.hideIndicator('se-act');
					ev.target.disabled = false;
				});
			}
		}, '重启服务');

		var actionsDiv = E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top: 20px;' }, [
			btnConnect, btnDisconnect, btnRestart
		]);

		m.appendChild(E('div', { 'class': 'cbi-section' }, [
			statusTable,
			actionsDiv
		]));

		// Live polling every 3 seconds
		poll.add(function() {
			return fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['status']).then(function(res) {
				var st = {};
				try { st = JSON.parse(res || '{}'); } catch(e) {}

				var elDaemon = document.getElementById('val_daemon');
				if (elDaemon) {
					elDaemon.innerHTML = st.running ?
						'<span class="badge badge-success">运行中 (PID: ' + (st.pid || 'N/A') + ')</span>' :
						'<span class="badge badge-danger">已停止</span>';
				}

				var elConn = document.getElementById('val_conn_status');
				if (elConn) {
					if (st.connection_status === 'Connected') {
						elConn.innerHTML = '<span class="badge badge-success">已连接</span>';
					} else if (st.connection_status === 'Connecting') {
						elConn.innerHTML = '<span class="badge badge-warning">正在连接...</span>';
					} else if (st.connection_status === 'Retrying') {
						elConn.innerHTML = '<span class="badge badge-warning">正在重试连接...</span>';
					} else {
						elConn.innerHTML = '<span class="badge badge-secondary">已断开</span>';
					}
				}

				var elDev = document.getElementById('val_device');
				if (elDev) elDev.textContent = (st.device || 'vpn_vpn0') + (st.device_up ? ' (已启用/UP)' : ' (未启用/DOWN)');

				var elIp = document.getElementById('val_ip');
				if (elIp) elIp.innerHTML = st.ip_address ? '<strong>' + st.ip_address + '</strong>' : '尚未分配 IP 地址';

				var elServer = document.getElementById('val_server_ip');
				if (elServer) elServer.textContent = st.server_ip || '暂无';

				var elSession = document.getElementById('val_session');
				if (elSession) elSession.textContent = st.session_name || '无活动会话';

				var elTraffic = document.getElementById('val_traffic');
				if (elTraffic) elTraffic.textContent = '接收 (RX): ' + self.formatBytes(st.rx_bytes) + ' | 发送 (TX): ' + self.formatBytes(st.tx_bytes);

				var btnConn = document.getElementById('btn_connect');
				var btnDisconn = document.getElementById('btn_disconnect');
				var isConn = (st.connection_status === 'Connected');
				if (btnConn) btnConn.style.display = isConn ? 'none' : '';
				if (btnDisconn) btnDisconn.style.display = isConn ? '' : 'none';
			});
		}, 3);

		return m;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
