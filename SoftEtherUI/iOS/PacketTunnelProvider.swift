// PacketTunnelProvider.swift
// iOS Packet Tunnel Extension for SoftEther VPN Client (ARM64)
// Provides bidirectional packet forwarding between TUN and SoftEther C core.

#if os(iOS)
import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var isTunnelRunning = false
    private let logger = Logger(subsystem: "com.softether.ui.PacketTunnel", category: "Provider")

    override func startTunnel(options: [String: NSObject]? = nil,
                              completionHandler: @escaping (Error?) -> Void) {
        logger.info("PacketTunnelProvider starting (arm64)...")

        guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
              let config = tunnelProtocol.providerConfiguration else {
            completionHandler(NSError(domain: "PacketTunnelProviderDomain", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Invalid Configuration"]))
            return
        }

        let serverAddress = tunnelProtocol.serverAddress ?? ""
        let hub = config["hub"] as? String ?? "VPNGATE"
        let username = config["username"] as? String ?? "vpn"

        logger.info("Connecting to Hub %{public}@ at %{public}@", hub, serverAddress)

        // TODO: Initialize SoftEther C core session via SE_* API.
        // The C core performs SSL handshake and returns assigned IP + DNS.
        let assignedIP = "10.0.8.2"
        let assignedDNS = ["1.1.1.1", "8.8.8.8"]

        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverAddress)

        let ipv4Settings = NEIPv4Settings(addresses: [assignedIP], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        networkSettings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: assignedDNS)
        dnsSettings.matchDomains = [""]
        networkSettings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(networkSettings) { error in
            if let err = error {
                self.logger.error("Failed to set tunnel settings: %{public}@", err.localizedDescription)
                completionHandler(err)
            } else {
                self.isTunnelRunning = true
                self.startPacketForwardingLoop()
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        logger.info("PacketTunnelProvider stopping (reason: %ld)", reason.rawValue)
        isTunnelRunning = false
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        let payload = String(data: messageData, encoding: .utf8) ?? ""
        if payload == "status" {
            let status: [String: String] = [
                "running": String(isTunnelRunning),
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
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.isTunnelRunning else { return }

            for (index, packet) in packets.enumerated() {
                // TODO: Forward to SE_ProcessOutboundPacket() when C core is linked.
                _ = index
                _ = protocols
                self.logger.debug("Outbound packet: %d bytes (awaiting C core link)", packet.count)
            }

            self.startPacketForwardingLoop()
        }
    }
}
#endif
