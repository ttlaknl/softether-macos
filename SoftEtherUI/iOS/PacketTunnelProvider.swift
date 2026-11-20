// PacketTunnelProvider.swift
// iOS & macOS NetworkExtension Packet Tunnel Provider for SoftEther VPN Client (ARM64)
// Uses SoftEtherTunnelSession (pure Swift SSL-VPN + L2/L3 ARP/DHCP bridge)

import NetworkExtension
import Network
import Foundation
import os.log

@objc(PacketTunnelProvider)
class PacketTunnelProvider: NEPacketTunnelProvider {

    private struct TunnelConfig {
        let host: String
        let resolvedIP: String
        let port: UInt16
        let hub: String
        let username: String
        let password: String
    }

    private let providerQueue = DispatchQueue(label: "org.softether.PacketTunnel.state", qos: .userInitiated)
    private var isTunnelRunning = false
    private var isStoppedByUser = false
    private var isReconnecting = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 6
    private var readLoopStarted = false

    private var activeConfig: TunnelConfig?
    private var session: SoftEtherTunnelSession?
    private var pathMonitor: NWPathMonitor?
    private var lastPathInterfaceType: NWInterface.InterfaceType?
    private var assignedIP: String = "192.168.30.18"
    private let logger = Logger(subsystem: "org.softether.SoftEtherUI.PacketTunnel", category: "Provider")

    // In-memory ring buffer for streaming provider & protocol logs to the main UI
    private var logBuffer: [String] = []
    private let logBufferLock = NSLock()

    private func logToApp(_ msg: String) {
        logger.info("\(msg, privacy: .public)")
        logBufferLock.lock()
        logBuffer.append(msg)
        if logBuffer.count > 200 {
            logBuffer.removeFirst(logBuffer.count - 200)
        }
        logBufferLock.unlock()
    }

    private func drainRecentLogs() -> [String] {
        logBufferLock.lock()
        defer { logBufferLock.unlock() }
        let logs = logBuffer
        logBuffer.removeAll()
        return logs
    }

    private func nameOfInterfaceType(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "Wi-Fi 无线网络"
        case .cellular: return "蜂窝移动数据 (4G/5G)"
        case .wiredEthernet: return "有线以太网"
        case .loopback: return "环回接口"
        case .other: return "其他网络接口"
        @unknown default: return "未知接口"
        }
    }

    private func describeStopReason(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none:
            return "正常退出 (无特定原因)"
        case .userInitiated:
            return "用户手动主动断开"
        case .providerFailed:
            return "PacketTunnelProvider 内部发生故障或崩溃 (providerFailed)"
        case .noNetworkAvailable:
            return "手机失去物理网络连接 (Wi-Fi 与蜂窝数据均不可用)"
        case .unrecoverableNetworkChange:
            return "物理网络发生不可恢复的切换 (Wi-Fi 断开且蜂窝未接管)"
        case .providerDisabled:
            return "VPN 插件配置被系统禁用 (providerDisabled)"
        case .authenticationCanceled:
            return "系统 VPN 认证已取消"
        case .configurationFailed:
            return "VPN 描述配置参数解析失败"
        case .idleTimeout:
            return "网络流量空闲超时 (系统判定长时间无有效数据流触发省电保护断开)"
        case .configurationDisabled:
            return "VPN 描述文件在系统设置中被禁用"
        case .configurationRemoved:
            return "VPN 描述文件已被系统或用户删除"
        case .superceded:
            return "连接被系统其他 VPN 配置文件抢占接管"
        case .userLogout:
            return "当前系统用户已注销"
        case .userSwitch:
            return "系统切换了活动用户"
        case .connectionFailed:
            return "底层网络连接失败 (TCP/TLS 握手失败或握手超时)"
        case .sleep:
            return "iOS 设备锁屏进入深度休眠 (Sleep) 触发系统切断网络"
        case .appUpdate:
            return "App 或扩展插件正在更新"
        @unknown default:
            return "未知系统停止原因 (代码: \(reason.rawValue))"
        }
    }

    override func startTunnel(options: [String: NSObject]? = nil,
                              completionHandler: @escaping (Error?) -> Void) {
        logToApp("[iOS NE] PacketTunnelProvider 隧道提供者正在启动 (ARM64)...")

        guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            completionHandler(NSError(domain: "PacketTunnelProviderDomain", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Invalid NETunnelProviderProtocol"]))
            return
        }

        let config = tunnelProtocol.providerConfiguration ?? [:]
        let rawServer = tunnelProtocol.serverAddress ?? "154.13.4.209:992"
        let hostParts = rawServer.split(separator: ":")
        let serverHost = hostParts.first.map(String.init) ?? "154.13.4.209"
        let serverPort = (config["port"] as? Int).flatMap { UInt16(exactly: $0) }
                      ?? (hostParts.count > 1 ? UInt16(hostParts[1]) : nil)
                      ?? 992
        let hub = config["hub"] as? String ?? "VPN"
        let username = config["username"] as? String ?? "vpn"
        let password = config["password"] as? String ?? "18102744"
        let resolvedIP = SoftEtherTunnelSession.resolveIPv4(host: serverHost) ?? serverHost

        let tunnelCfg = TunnelConfig(
            host: serverHost,
            resolvedIP: resolvedIP,
            port: serverPort,
            hub: hub,
            username: username,
            password: password
        )

        providerQueue.async { [weak self] in
            guard let self = self else { return }
            self.isStoppedByUser = false
            self.isReconnecting = false
            self.reconnectAttempt = 0
            self.readLoopStarted = false
            self.activeConfig = tunnelCfg

            self.logToApp("[iOS NE] 发起底层隧道连接 -> \(serverHost):\(serverPort) (Hub: \(hub), User: \(username))")

            let vpnSession = self.createSession(for: tunnelCfg)
            self.session = vpnSession

            vpnSession.start { [weak self] result in
                guard let self = self else { return }
                self.providerQueue.async {
                    guard !self.isStoppedByUser else { return }
                    switch result {
                    case .failure(let err):
                        let errDesc = SoftEtherTunnelSession.formatNWError(err)
                        self.logToApp("[断线监测] SoftEther 握手失败: \(errDesc)")
                        self.session = nil
                        completionHandler(err)

                    case .success(let info):
                        self.applyNetworkSettings(info: info, config: tunnelCfg) { err in
                            self.providerQueue.async {
                                if let err = err {
                                    self.logToApp("[断线监测] 应用虚拟网卡配置失败: \(err.localizedDescription)")
                                    vpnSession.stop()
                                    self.session = nil
                                    completionHandler(err)
                                } else {
                                    self.isTunnelRunning = true
                                    self.logToApp("[iOS Success] 虚拟网卡配置就绪，IP: \(info.assignedIP), MTU: 1280")
                                    self.startNetworkPathMonitor()
                                    self.ensurePacketForwardingLoopStarted()
                                    completionHandler(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func createSession(for cfg: TunnelConfig) -> SoftEtherTunnelSession {
        let vpnSession = SoftEtherTunnelSession(
            host: cfg.resolvedIP,
            port: cfg.port,
            hub: cfg.hub,
            username: cfg.username,
            password: cfg.password
        )

        vpnSession.onLog = { [weak self] msg in
            self?.logToApp(msg)
        }

        vpnSession.onInboundIPPackets = { [weak self] ipPackets in
            guard let self = self, self.isTunnelRunning, !ipPackets.isEmpty else { return }
            let protos = Array(repeating: NSNumber(value: AF_INET), count: ipPackets.count)
            self.packetFlow.writePackets(ipPackets, withProtocols: protos)
        }

        vpnSession.onDisconnect = { [weak self, weak vpnSession] err in
            self?.providerQueue.async {
                guard let self = self,
                      let vpnSession = vpnSession,
                      self.session === vpnSession else { return }
                self.handleSessionDisconnected(err)
            }
        }

        return vpnSession
    }

    private func applyNetworkSettings(info: SoftEtherTunnelSession.HandshakeResult,
                                      config: TunnelConfig,
                                      completion: @escaping (Error?) -> Void) {
        self.assignedIP = info.assignedIP
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: config.resolvedIP)
        networkSettings.mtu = 1280

        let ipv4Settings = NEIPv4Settings(addresses: [info.assignedIP], subnetMasks: [info.subnetMask])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        // Exclude the VPN server itself from tunnel route to prevent routing loop
        ipv4Settings.excludedRoutes = [
            NEIPv4Route(destinationAddress: config.resolvedIP, subnetMask: "255.255.255.255")
        ]
        networkSettings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: info.dnsServers)
        dnsSettings.matchDomains = [""]
        networkSettings.dnsSettings = dnsSettings

        self.setTunnelNetworkSettings(networkSettings, completionHandler: completion)
    }

    private func startNetworkPathMonitor() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.providerQueue.async {
                guard let self = self,
                      self.isTunnelRunning,
                      !self.isStoppedByUser else { return }
                let newType: NWInterface.InterfaceType? =
                    path.usesInterfaceType(.wifi) ? .wifi :
                    path.usesInterfaceType(.cellular) ? .cellular :
                    path.usesInterfaceType(.wiredEthernet) ? .wiredEthernet : nil

                if let prev = self.lastPathInterfaceType,
                   let cur = newType,
                   prev != cur {
                    let prevName = self.nameOfInterfaceType(prev)
                    let curName = self.nameOfInterfaceType(cur)
                    self.logToApp("[网络切换监测] 物理底层网络接口变更: \(prevName) -> \(curName) (状态: \(path.status))")
                    if path.status == .satisfied && !self.isReconnecting {
                        self.logToApp("[网络切换监测] 正在根据新网络接口主动重连 SoftEther 隧道...")
                        self.handleSessionDisconnected(nil)
                    }
                }
                if path.status != .satisfied {
                    self.logToApp("[网络切换监测] 物理底层网络当前不可用 (Path: \(path.status))")
                }
                if newType != nil {
                    self.lastPathInterfaceType = newType
                }
            }
        }
        monitor.start(queue: providerQueue)
        self.pathMonitor = monitor
    }

    private func handleSessionDisconnected(_ error: Error?) {
        guard !isStoppedByUser, isTunnelRunning, !isReconnecting else { return }
        isReconnecting = true
        reconnectAttempt = 0
        session?.stop()
        session = nil
        reasserting = true
        let errDesc = error != nil ? SoftEtherTunnelSession.formatNWError(error!) : "服务端主动断开或物理网络切换"
        logToApp("[断线监测] 隧道会话中断: \(errDesc)，启动后台自动重连机制...")
        attemptReconnect(lastError: error)
    }

    private func attemptReconnect(lastError: Error?) {
        guard !isStoppedByUser, isTunnelRunning, let cfg = activeConfig else {
            isReconnecting = false
            reasserting = false
            return
        }

        reconnectAttempt += 1
        if reconnectAttempt > maxReconnectAttempts {
            logToApp("[断线监测] ❌ 已达最大自动重连尝试次数 (\(self.maxReconnectAttempts) 次)，停止隧道")
            isTunnelRunning = false
            isReconnecting = false
            reasserting = false
            let finalErr = lastError ?? NSError(domain: "PacketTunnelProviderDomain", code: -2,
                                                userInfo: [NSLocalizedDescriptionKey: "SoftEther 隧道断线后重连失败"])
            cancelTunnelWithError(finalErr)
            return
        }

        let delaySec = min(Double(reconnectAttempt) * 2.0, 8.0)
        logToApp("[断线监测] 正在发起第 \(self.reconnectAttempt)/\(self.maxReconnectAttempts) 次原地重连 (等待 \(String(format: "%.1f", delaySec)) 秒)...")

        providerQueue.asyncAfter(deadline: .now() + delaySec) { [weak self] in
            guard let self = self, !self.isStoppedByUser, self.isTunnelRunning else { return }
            let newSession = self.createSession(for: cfg)
            self.session = newSession

            newSession.start { [weak self, weak newSession] result in
                self?.providerQueue.async {
                    guard let self = self,
                          !self.isStoppedByUser,
                          self.isTunnelRunning,
                          let newSession = newSession,
                          self.session === newSession else { return }

                    switch result {
                    case .failure(let err):
                        let errDesc = SoftEtherTunnelSession.formatNWError(err)
                        self.logToApp("[断线监测] ⚠️ 第 \(self.reconnectAttempt) 次重连失败: \(errDesc)")
                        newSession.stop()
                        self.session = nil
                        self.attemptReconnect(lastError: err)

                    case .success(let info):
                        let ipChanged = (info.assignedIP != self.assignedIP)
                        self.assignedIP = info.assignedIP
                        if ipChanged {
                            self.applyNetworkSettings(info: info, config: cfg) { err in
                                self.providerQueue.async {
                                    if let err = err {
                                        self.logToApp("[断线监测] 重连后更新网络配置失败: \(err.localizedDescription)")
                                        newSession.stop()
                                        self.session = nil
                                        self.attemptReconnect(lastError: err)
                                    } else {
                                        self.isReconnecting = false
                                        self.reconnectAttempt = 0
                                        self.reasserting = false
                                        self.logToApp("[断线监测] ✅ 隧道已成功恢复连接！(更新分配 IP: \(info.assignedIP))")
                                    }
                                }
                            }
                        } else {
                            self.isReconnecting = false
                            self.reconnectAttempt = 0
                            self.reasserting = false
                            self.logToApp("[断线监测] ✅ 隧道已成功恢复连接！(保持分配 IP: \(info.assignedIP))")
                        }
                    }
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        let reasonDesc = describeStopReason(reason)
        let logMsg = "[系统断线监测] iOS 系统主动停止 VPN 隧道 -> 原因: \(reasonDesc) (代码: \(reason.rawValue))"
        logToApp(logMsg)

        let sharedDefaults = UserDefaults(suiteName: "group.org.softether.SoftEtherUI")
        sharedDefaults?.set(logMsg, forKey: "last_tunnel_disconnect_reason")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "last_tunnel_disconnect_time")
        sharedDefaults?.synchronize()

        providerQueue.async { [weak self] in
            guard let self = self else {
                completionHandler()
                return
            }
            self.isStoppedByUser = true
            self.isTunnelRunning = false
            self.isReconnecting = false
            self.readLoopStarted = false
            self.reasserting = false
            self.pathMonitor?.cancel()
            self.pathMonitor = nil
            self.session?.stop()
            self.session = nil
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        let payload = String(data: messageData, encoding: .utf8) ?? ""
        if payload == "status" {
            providerQueue.async { [weak self] in
                guard let self = self else {
                    completionHandler?(nil)
                    return
                }
                let logs = self.drainRecentLogs()
                let status: [String: Any] = [
                    "running": String(self.isTunnelRunning),
                    "reconnecting": String(self.isReconnecting),
                    "assignedIP": self.assignedIP,
                    "bytesSent": String(self.session?.totalBytesSent ?? 0),
                    "bytesRecv": String(self.session?.totalBytesRecv ?? 0),
                    "version": "2.3.1",
                    "arch": "arm64",
                    "recentLogs": logs
                ]
                if let data = try? JSONSerialization.data(withJSONObject: status) {
                    completionHandler?(data)
                } else {
                    completionHandler?(nil)
                }
            }
            return
        }
        completionHandler?(nil)
    }

    private func ensurePacketForwardingLoopStarted() {
        guard !readLoopStarted else { return }
        readLoopStarted = true
        startPacketForwardingLoop()
    }

    private func startPacketForwardingLoop() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, self.isTunnelRunning, !self.isStoppedByUser else { return }

            if !packets.isEmpty {
                self.session?.sendIPv4Packets(packets)
            }

            self.startPacketForwardingLoop()
        }
    }
}
