// PacketTunnelProvider.swift
// iOS & macOS NetworkExtension Packet Tunnel Provider for SoftEther VPN Client (ARM64)
// Uses SoftEtherTunnelSession (pure Swift SSL-VPN + L2/L3 ARP/DHCP bridge)

import NetworkExtension
import Foundation
import os.log

@objc(PacketTunnelProvider)
class PacketTunnelProvider: NEPacketTunnelProvider {

    private var isTunnelRunning = false
    private var session: SoftEtherTunnelSession?
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

        logger.info("Connecting to SoftEther Hub %{public}@ at %{public}@:%d", hub, serverHost, serverPort)

        let vpnSession = SoftEtherTunnelSession(
            host: serverHost,
            port: serverPort,
            hub: hub,
            username: username,
            password: password
        )

        vpnSession.onLog = { [weak self] msg in
            self?.logger.info("%{public}@", msg)
        }

        vpnSession.onInboundIPPacket = { [weak self] ipPacket in
            guard let self = self, self.isTunnelRunning else { return }
            self.packetFlow.writePackets([ipPacket], withProtocols: [NSNumber(value: AF_INET)])
        }

        self.session = vpnSession

        vpnSession.start { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                self.logger.error("SoftEther handshake failed: %{public}@", err.localizedDescription)
                completionHandler(err)

            case .success(let info):
                self.assignedIP = info.assignedIP
                let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverHost)
                networkSettings.mtu = 1280

                let ipv4Settings = NEIPv4Settings(addresses: [info.assignedIP], subnetMasks: [info.subnetMask])
                ipv4Settings.includedRoutes = [NEIPv4Route.default()]
                // Exclude the VPN server itself from tunnel route to prevent routing loop
                ipv4Settings.excludedRoutes = [
                    NEIPv4Route(destinationAddress: serverHost, subnetMask: "255.255.255.255")
                ]
                networkSettings.ipv4Settings = ipv4Settings

                let dnsSettings = NEDNSSettings(servers: info.dnsServers)
                dnsSettings.matchDomains = [""]
                networkSettings.dnsSettings = dnsSettings

                self.setTunnelNetworkSettings(networkSettings) { error in
                    if let err = error {
                        self.logger.error("Failed to set tunnel network settings: %{public}@", err.localizedDescription)
                        vpnSession.stop()
                        completionHandler(err)
                    } else {
                        self.isTunnelRunning = true
                        self.startPacketForwardingLoop()
                        completionHandler(nil)
                    }
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        logger.info("PacketTunnelProvider stopping (reason: %ld)", reason.rawValue)
        isTunnelRunning = false
        session?.stop()
        session = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        let payload = String(data: messageData, encoding: .utf8) ?? ""
        if payload == "status" {
            let status: [String: String] = [
                "running": String(isTunnelRunning),
                "assignedIP": assignedIP,
                "bytesSent": String(session?.totalBytesSent ?? 0),
                "bytesRecv": String(session?.totalBytesRecv ?? 0),
                "version": "2.3.0",
                "arch": "arm64"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: status) {
                completionHandler?(data)
                return
            }
        }
        completionHandler?(nil)
    }

    private func startPacketForwardingLoop() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, self.isTunnelRunning else { return }

            for packet in packets {
                self.session?.sendIPv4Packet(packet)
            }

            self.startPacketForwardingLoop()
        }
    }
}
