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

    override func startTunnel(options: [String: NSObject]? = nil,
                              completionHandler: @escaping (Error?) -> Void) {
        logger.info("PacketTunnelProvider starting (ARM64)...")

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

            self.logger.info("Connecting to SoftEther Hub \(hub, privacy: .public) at \(serverHost, privacy: .public):\(serverPort)")

            let vpnSession = self.createSession(for: tunnelCfg)
            self.session = vpnSession

            vpnSession.start { [weak self] result in
                guard let self = self else { return }
                self.providerQueue.async {
                    guard !self.isStoppedByUser else { return }
                    switch result {
                    case .failure(let err):
                        self.logger.error("SoftEther handshake failed: \(err.localizedDescription, privacy: .public)")
                        self.session = nil
                        completionHandler(err)

                    case .success(let info):
                        self.applyNetworkSettings(info: info, config: tunnelCfg) { err in
                            self.providerQueue.async {
                                if let err = err {
                                    self.logger.error("Failed to set tunnel network settings: \(err.localizedDescription, privacy: .public)")
                                    vpnSession.stop()
                                    self.session = nil
                                    completionHandler(err)
                                } else {
                                    self.isTunnelRunning = true
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
            self?.logger.info("\(msg, privacy: .public)")
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
                   prev != cur,
                   path.status == .satisfied,
                   !self.isReconnecting {
                    self.logger.info("Physical network interface switched; proactively reconnecting SoftEther tunnel...")
                    self.handleSessionDisconnected(nil)
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
        logger.warning("SoftEther session interrupted (\(error?.localizedDescription ?? "EOF", privacy: .public)); starting auto-reconnect...")
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
            logger.error("Exceeded \(self.maxReconnectAttempts) reconnect attempts; stopping tunnel.")
            isTunnelRunning = false
            isReconnecting = false
            reasserting = false
            let finalErr = lastError ?? NSError(domain: "PacketTunnelProviderDomain", code: -2,
                                                userInfo: [NSLocalizedDescriptionKey: "SoftEther 隧道断线后重连失败"])
            cancelTunnelWithError(finalErr)
            return
        }

        let delaySec = min(Double(reconnectAttempt) * 2.0, 8.0)
        logger.info("Reconnect attempt #\(self.reconnectAttempt)/\(self.maxReconnectAttempts) in \(delaySec)s...")

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
                        self.logger.warning("Reconnect attempt #\(self.reconnectAttempt) failed: \(err.localizedDescription, privacy: .public)")
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
                                        self.logger.error("Failed to update network settings after reconnect: \(err.localizedDescription, privacy: .public)")
                                        newSession.stop()
                                        self.session = nil
                                        self.attemptReconnect(lastError: err)
                                    } else {
                                        self.isReconnecting = false
                                        self.reconnectAttempt = 0
                                        self.reasserting = false
                                        self.logger.info("SoftEther tunnel reconnected cleanly (IP updated: \(info.assignedIP, privacy: .public))")
                                    }
                                }
                            }
                        } else {
                            self.isReconnecting = false
                            self.reconnectAttempt = 0
                            self.reasserting = false
                            self.logger.info("SoftEther tunnel reconnected cleanly (IP preserved: \(info.assignedIP, privacy: .public))")
                        }
                    }
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        logger.info("PacketTunnelProvider stopping (reason: \(reason.rawValue))")
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
                let status: [String: String] = [
                    "running": String(self.isTunnelRunning),
                    "reconnecting": String(self.isReconnecting),
                    "assignedIP": self.assignedIP,
                    "bytesSent": String(self.session?.totalBytesSent ?? 0),
                    "bytesRecv": String(self.session?.totalBytesRecv ?? 0),
                    "version": "2.3.1",
                    "arch": "arm64"
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
