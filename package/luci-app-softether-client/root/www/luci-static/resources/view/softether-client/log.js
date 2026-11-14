'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return fs.exec_direct('/sbin/logread', ['-e', 'softether']).catch(function() {
			return '暂未获取到相关日志记录。';
		});
	},

	render: function(logdata) {
		var logTextarea = E('pre', {
			'class': 'cbi-input-textarea',
			'style': 'width: 100%; height: 300px; overflow-y: scroll; font-family: monospace; font-size: 12px; background: #1e1e1e; color: #d4d4d4; padding: 10px; border-radius: 4px;'
		}, logdata || '暂未获取到相关日志记录。');

		var btnRefresh = E('button', {
			'class': 'btn cbi-button-action',
			'click': function(ev) {
				ev.target.disabled = true;
				fs.exec_direct('/sbin/logread', ['-e', 'softether']).then(function(res) {
					logTextarea.textContent = res || '暂未获取到相关日志记录。';
					ev.target.disabled = false;
				}).catch(function() {
					ev.target.disabled = false;
				});
			}
		}, '刷新日志');

		var cmdInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width: 65%; display: inline-block; margin-right: 10px;',
			'placeholder': '例如：AccountStatusGet default 或 NicList 或 AccountList'
		});

		var cmdOutput = E('pre', {
			'style': 'width: 100%; min-height: 150px; max-height: 400px; overflow-y: scroll; font-family: monospace; font-size: 12px; background: #000; color: #00ff00; padding: 10px; margin-top: 10px; border-radius: 4px;'
		}, '在上方输入指令后，点击【执行指令】即可向本机 SoftEther 客户端发送控制指令并实时显示返回结果。');

		var btnExec = E('button', {
			'class': 'btn cbi-button-apply',
			'click': function(ev) {
				var cmd = cmdInput.value.trim();
				if (!cmd) return;
				ev.target.disabled = true;
				cmdOutput.textContent = '正在执行指令: ' + cmd + ' ...';
				fs.exec_direct('/usr/libexec/softether/softether-helper.sh', ['cmd', cmd]).then(function(res) {
					cmdOutput.textContent = res || '(指令执行完毕，无输出内容)';
					ev.target.disabled = false;
				}).catch(function(err) {
					cmdOutput.textContent = '执行失败: ' + (err.message || err);
					ev.target.disabled = false;
				});
			}
		}, '执行指令');

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'SoftEther VPN 客户端 - 运行日志与诊断'),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '系统运行日志 (包含 softether 标识)'),
				logTextarea,
				E('div', { 'style': 'margin-top: 10px;' }, [ btnRefresh ])
			]),

			E('div', { 'class': 'cbi-section', 'style': 'margin-top: 25px;' }, [
				E('h3', {}, '交互式 vpncmd 底层诊断控制台'),
				E('div', { 'class': 'cbi-map-descr' }, '直接向本机 SoftEther VPN 客户端进程发送管理指令，便于高级用户快速诊断网络与会话状态。'),
				E('div', {}, [ cmdInput, btnExec ]),
				cmdOutput
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
