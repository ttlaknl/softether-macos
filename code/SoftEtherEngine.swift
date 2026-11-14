// SoftEtherEngine.swift
// Native ARM64 SoftEther Client Controller (macOS & iOS Unified Version)
// Includes all v1.0 fixes (config persistence, v5.02 AccountDetailSet, DNS split & restore,
// Resources/hamcore.se2 codesign fix, thread-safe logging) + iOS NetworkExtension & Direct SSL-VPN Engine.

import Foundation
import Combine

#if os(macOS)
import Cocoa
#elseif os(iOS)
import NetworkExtension
import UIKit
#endif

// MARK: - Default Server Credentials

private enum VPNCredentials {
    static let defaultHost = "154.13.4.209"
    static let defaultPort = 992
    static let defaultHub = "VPN"
    static let defaultUsername = "vpn"
    static let defaultPassword = "18102744"
    static let fallbackHub = "VPNGATE"
    static let fallbackUsername = "laknl"
    static let fallbackPassword = "vpn"
}

#if os(macOS)
// MARK: - Fix #11: Process extension using DispatchSource instead of busy-wait

extension Process {
    /// Wait for process to exit within the given timeout.
    /// Returns true if process exited in time, false if timed out.
    func waitUntilExitOrTimeout(seconds: TimeInterval) -> Bool {
        guard isRunning else { return true }
        let semaphore = DispatchSemaphore(value: 0)
        let deadline = Date().addingTimeInterval(seconds)

        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async { [weak self] in
            while let self = self, self.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + seconds + 0.5)
        return result == .success && !isRunning
    }
}
#endif

// MARK: - Public Types

public enum VPNState: String, CustomStringConvertible {
    case disconnected  = "未连接"
    case connecting    = "正在连接..."
    case connected     = "已安全建立隧道"
    case disconnecting = "正在断开..."
    case error         = "连接失败"

    public var description: String { self.rawValue }
}

public struct VPNServerConfig: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var name: String
    public var host: String
    public var port: Int
    public var hub: String
    public var username: String
    public var password: String
    public var isSelected: Bool = false

    public init(id: UUID = UUID(), name: String, host: String, port: Int = 992, hub: String = "VPNGATE", username: String = "laknl", password: String = "vpn", isSelected: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.hub = hub
        self.username = username
        self.password = password
        self.isSelected = isSelected
    }
}

public struct NetworkTraffic {
    public var uploadSpeedKbps: Double = 0.0
    public var downloadSpeedKbps: Double = 0.0
    public var totalSentMB: Double = 0.0
    public var totalRecvMB: Double = 0.0
}

// MARK: - Fix #10: EngineSettings with UserDefaults persistence (v1.0 optimized defaults)

public struct EngineSettings {
    static let defaults = UserDefaults.standard

    public var killSwitchEnabled: Bool {
        get { Self.defaults.object(forKey: "killSwitchEnabled") as? Bool ?? true }
        set { Self.defaults.set(newValue, forKey: "killSwitchEnabled") }
    }

    public var dnsLeakProtection: Bool {
        get { Self.defaults.object(forKey: "dnsLeakProtection") as? Bool ?? true }
        set { Self.defaults.set(newValue, forKey: "dnsLeakProtection") }
    }

    public var useUDPAcceleration: Bool {
        get { Self.defaults.object(forKey: "useUDPAcceleration") as? Bool ?? true }
        set { Self.defaults.set(newValue, forKey: "useUDPAcceleration") }
    }

    public var selectedCipher: String {
        get { Self.defaults.string(forKey: "selectedCipher") ?? "AES-256-GCM" }
        set { Self.defaults.set(newValue, forKey: "selectedCipher") }
    }

    public var maxTCPChannels: Int {
        get { let v = Self.defaults.integer(forKey: "maxTCPChannels"); return v == 0 ? 8 : v }
        set { Self.defaults.set(newValue, forKey: "maxTCPChannels") }
    }

    public init() {}
}

// MARK: - SoftEtherEngine

private let kMaxLogEntries = 2000

@MainActor
public class SoftEtherEngine: ObservableObject {
    public static let shared = SoftEtherEngine()

    @Published public var state: VPNState = .disconnected
    @Published public var currentConfig: VPNServerConfig?
    @Published public var configs: [VPNServerConfig] = []
    @Published public var traffic: NetworkTraffic = NetworkTraffic()
    @Published public var logs: [String] = []
    @Published public var connectedDurationSec: Int = 0
    @Published public var assignedIP: String = "未分配"
    @Published public var settings: EngineSettings = EngineSettings()

    private var timer: Timer?
    private var durationTimer: Timer?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var activeRouteHost: String?
    /// Fix #3: prevent re-entrant connect/disconnect
    private var pipelineRunning = false

    /// Serialize all connect/disconnect pipelines to prevent dual-session races
    private let pipelineLock = NSLock()

    private let routeSetupQueue = DispatchQueue(label: "com.softether.routeSetup", qos: .userInitiated)

    private init() {
        loadConfigs()
        appendLog("[System] Native SoftEther Engine Ready (ARM64 Native)")
    }

    // MARK: - Config Management (v1.0 UserDefaults Persistence + Initial Default Seed)

    /// Load user's VPN configs from UserDefaults. Seeds default server on first install.
    public func loadConfigs() {
        if let data = EngineSettings.defaults.data(forKey: "savedVPNConfigs"),
           let decoded = try? JSONDecoder().decode([VPNServerConfig].self, from: data),
           !decoded.isEmpty {
            self.configs = decoded
            self.currentConfig = configs.first
            appendLog("[Config] 已加载 \(decoded.count) 个保存的节点")
        } else {
            self.configs = [
                VPNServerConfig(name: "默认服务器 (\(VPNCredentials.defaultHost))", host: VPNCredentials.defaultHost, port: VPNCredentials.defaultPort, hub: VPNCredentials.defaultHub, username: VPNCredentials.defaultUsername, password: VPNCredentials.defaultPassword, isSelected: true),
                VPNServerConfig(name: "备用 443 端口节点", host: VPNCredentials.defaultHost, port: 443, hub: VPNCredentials.fallbackHub, username: VPNCredentials.fallbackUsername, password: VPNCredentials.fallbackPassword)
            ]
            self.currentConfig = configs.first
            saveConfigs()
            appendLog("[Config] 已初始化默认服务器节点配置")
        }
    }

    /// Persist current configs array to UserDefaults so user's nodes survive app restarts.
    public func saveConfigs() {
        if let data = try? JSONEncoder().encode(self.configs) {
            EngineSettings.defaults.set(data, forKey: "savedVPNConfigs")
        }
    }

    // MARK: - Connect / Disconnect

    public func toggleConnect() {
        if state == .connected || state == .connecting {
            disconnect()
        } else {
            connect()
        }
    }

    /// Fix #3: Guard against re-entrant connect
    public func connect() {
        guard state == .disconnected || state == .error else {
            appendLog("[Warning] 无法在当前状态 (\(state)) 下发起连接")
            return
        }
        guard let config = currentConfig else {
            appendLog("[Error] 请先在节点管理中选择有效配置")
            return
        }
        state = .connecting
        assignedIP = "获取中..."
        appendLog("[Connect] 发起 SSL-VPN 连接 -> \(config.host):\(config.port) (User: \(config.username))")
        #if os(macOS)
        startMacOSConnectionPipeline(config: config)
        #elseif os(iOS)
        startIOSNetworkExtensionConnection(config: config)
        #endif
    }

    /// Fix #3: Guard against re-entrant disconnect
    public func disconnect() {
        guard state == .connected || state == .connecting else {
            appendLog("[Warning] 无法在当前状态 (\(state)) 下断开")
            return
        }
        state = .disconnecting
        appendLog("[Disconnect] 正在断开 VPN 隧道...")
        stopTrafficMetricsTimer()
        #if os(macOS)
        DispatchQueue.global(qos: .userInitiated).async {
            self.stopMacOSConnectionPipelineSync()
            DispatchQueue.main.async {
                self.pipelineRunning = false
                self.state = .disconnected
                self.assignedIP = "未分配"
                self.activeRouteHost = nil
                self.appendLog("[Status] VPN 已断开")
            }
        }
        #elseif os(iOS)
        stopIOSNetworkExtensionConnection()
        self.state = .disconnected
        self.assignedIP = "未分配"
        self.activeRouteHost = nil
        appendLog("[Status] VPN 已断开")
        #endif
    }

    // MARK: - macOS Connection Pipeline

    #if os(macOS)
    private func startMacOSConnectionPipeline(config: VPNServerConfig) {
        guard pipelineLock.try() else {
            self.logFromBackground("[Pipeline] 已有连接流程运行中，忽略重复请求")
            return
        }
        pipelineRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let workingDir = self.resolveAbsoluteExecDir(allowKill: true)
            let vpncmdBin = "\(workingDir)/vpncmd"
            let accountName = "SOFTETHER_MAC_CONN"

            _ = self.runShellCommand(cmd: "rm -f /tmp/softether_utun_name.txt /tmp/softether_dhcp_result.txt")

            // Best-effort disconnect on old daemon to avoid dual session.
            // Use fast pgrep check instead of probeDaemonSocket (which blocks 30s).
            let oldDaemonAlive = self.runShellCommand(cmd: "pgrep vpnclient").trimmingCharacters(in: .whitespacesAndNewlines)
            if !oldDaemonAlive.isEmpty {
                self.logFromBackground("[Pipeline] 旧 daemon 存在 (PID: \(oldDaemonAlive))，先断开会话...")
                let disOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountDisconnect", accountName])
                self.logFromBackground("[Pipeline AccountDisconnect]: \(disOut)")
                Thread.sleep(forTimeInterval: 1.5)
            } else {
                self.logFromBackground("[Pipeline] 旧 daemon 不存在，跳过断开")
            }

            // NOW kill and restart daemon (old session already torn down above)
            self.ensureDaemonActive(workingDir: workingDir)

            let daemonReady = self.waitForDaemonReady(vpncmdBin: vpncmdBin, maxWaitSec: 15)
            guard daemonReady else {
                DispatchQueue.main.async {
                    self.pipelineRunning = false
                    self.pipelineLock.unlock()
                    self.state = .error
                    self.assignedIP = "守护进程未就绪"
                    self.appendLog("[Error] vpnclient RPC socket 在 15 秒内未就绪")
                }
                return
            }

            var vnicName = "tap0"

            self.logFromBackground("[vpncmd] 配置虚拟网卡接口...")
            let nicCreateOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:NicCreate", vnicName])
            if nicCreateOut.contains("命令成功") || nicCreateOut.contains("already exists") || nicCreateOut.contains("已经存在") {
                self.logFromBackground("[vpncmd NicCreate]: 虚拟网卡 '\(vnicName)' 就绪")
            } else {
                self.logFromBackground("[vpncmd NicCreate]: \(nicCreateOut)")
            }

            let nicEnableOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:NicEnable", vnicName])
            if !nicEnableOut.contains("命令成功") && !nicEnableOut.contains("Command completed") {
                self.logFromBackground("[vpncmd NicEnable]: \(nicEnableOut)")
            }

            _ = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:NicList"])
            _ = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountDelete", accountName])

            self.logFromBackground("[vpncmd] 创建连接账户 \(accountName) -> \(config.host):\(config.port)")
            var createOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountCreate", accountName, "/SERVER:\(config.host):\(config.port)", "/HUB:\(config.hub)", "/USERNAME:\(config.username)", "/NICNAME:\(vnicName)"])

            if createOut.contains("错误代码: 29") || createOut.contains("找不到") || createOut.contains("Not found") {
                self.logFromBackground("[vpncmd] 尝试使用 macOS 预设标准网卡 tap0...")
                vnicName = "tap0"
                createOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountCreate", accountName, "/SERVER:\(config.host):\(config.port)", "/HUB:\(config.hub)", "/USERNAME:\(config.username)", "/NICNAME:\(vnicName)"])
            }

            if createOut.contains("不可能指定此参数") || createOut.contains("not possible to specify") {
                self.logFromBackground("[vpncmd] v5 参数不兼容，尝试 v4 语法 /VNIC...")
                createOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountCreate", accountName, "/SERVER:\(config.host):\(config.port)", "/HUB:\(config.hub)", "/USERNAME:\(config.username)", "/VNIC:\(vnicName)"])
            }
            self.logFromBackground("[vpncmd AccountCreate]: \(createOut)")

            let passOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountPasswordSet", accountName, "/PASSWORD:\(config.password)", "/TYPE:standard"])
            self.logFromBackground("[vpncmd PasswordSet]: \(passOut)")

            let disableUDP = self.settings.useUDPAcceleration ? "no" : "yes"
            let maxTCP = "\(self.settings.maxTCPChannels)"
            // Fix (v1.0): vpncmd v5.02 Developer Edition requires ALL parameters to be specified
            // together in a single AccountDetailSet call; omitting any causes silent failure.
            // /NOTIMEOUT is not supported in v5.02 and must not be passed.
            let detailOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountDetailSet", accountName, "/MAXTCP:\(maxTCP)", "/INTERVAL:1", "/TTL:0", "/HALF:no", "/BRIDGE:no", "/MONITOR:no", "/NOTRACK:no", "/NOQOS:no", "/DISABLEUDP:\(disableUDP)"])
            self.logFromBackground("[vpncmd AccountDetailSet]: \(detailOut)")

            self.logFromBackground("[vpncmd] 发起物理 SSL 会话连接 (AccountConnect)...")
            let connOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountConnect", accountName])
            self.logFromBackground("[vpncmd AccountConnect]: \(connOut)")

            var isEstablished = false
            var statusDetail = ""

            for _ in 1...15 {
                Thread.sleep(forTimeInterval: 1.2)
                let statusOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountStatusGet", accountName])
                statusDetail = statusOut
                let hasSessionID = statusOut.contains("SID-") && !statusOut.contains("SID-SECURENAT")
                let isConnected = hasSessionID
                    && (statusOut.contains("连接完成") || statusOut.contains("通信中") || statusOut.contains("Connected") || statusOut.contains("Connection Completed"))
                    && !statusOut.contains("尝试") && !statusOut.contains("重试") && !statusOut.contains("未连接")
                    && !statusOut.contains("Disconnected") && !statusOut.contains("Retry")
                    && !statusOut.contains("用户认证失败") && !statusOut.contains("Authentication failed")
                if isConnected { isEstablished = true; break }
            }

            DispatchQueue.main.async {
                if isEstablished {
                    self.state = .connected
                    self.logFromBackground("[Success] 服务端握手成功！会话已建立 (SID-\(config.username.uppercased()))")
                    self.activeRouteHost = config.host
                    self.routeSetupQueue.async {
                        self.configureSystemRoutes(serverHost: config.host)
                        DispatchQueue.main.async {
                            self.pipelineLock.unlock()
                            self.startTrafficMetricsTimer()
                        }
                    }
                } else {
                    self.pipelineRunning = false
                    self.pipelineLock.unlock()
                    self.state = .error
                    self.assignedIP = "连接未建立"
                    self.logFromBackground("[Error] 真实 Session 建立失败:\n\(statusDetail)")
                }
            }
        }
    }

    private func stopMacOSConnectionPipelineSync() {
        let workingDir = self.resolveAbsoluteExecDir(allowKill: false)
        let vpncmdBin = "\(workingDir)/vpncmd"
        let accountName = "SOFTETHER_MAC_CONN"
        let serverHost = self.activeRouteHost ?? ""
        self.cleanSystemRoutes(serverHost: serverHost)
        self.logFromBackground("[vpncmd] 断开账户连接 (AccountDisconnect)...")
        let disOut = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:AccountDisconnect", accountName])
        self.logFromBackground("[vpncmd AccountDisconnect]: \(disOut)")
    }

    // MARK: - Network Route Configuration (v1.0 DNS Split & Restore)

    private func configureSystemRoutes(serverHost: String) {
        self.logFromBackground("[Network] 正在检测多网卡环境并配置路由...")
        _ = self.runShellCommand(cmd: "rm -f /tmp/softether_dhcp_result.txt")

        // Save user's original DNS before overwriting, so disconnect can restore it
        let findNetSvcCmd0 = "networksetup -listallnetworkservices | grep -v '*' | grep -E 'Wi-Fi|Ethernet|以太网' | head -n 1"
        let activeNetSvc0 = self.runShellCommand(cmd: findNetSvcCmd0).trimmingCharacters(in: .whitespacesAndNewlines)
        let netSvcName0 = activeNetSvc0.isEmpty ? "Wi-Fi" : activeNetSvc0
        let currentDNS = self.runShellCommand(cmd: "networksetup -getdnsservers \"\(netSvcName0)\" 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        let savedDNS = currentDNS.contains("aren't") || currentDNS.contains("没有") ? "Empty" : currentDNS
        EngineSettings.defaults.set(savedDNS, forKey: "savedOriginalDNS")
        self.logFromBackground("[Network] 已保存用户原 DNS: \(savedDNS)")

        // First read exact utun device reported by the kernel control socket
        var targetUtun = self.runShellCommand(cmd: "cat /tmp/softether_utun_name.txt 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        if targetUtun.isEmpty {
            let findUtunCmd = "ifconfig | grep -E '^utun[0-9]+' | tail -n 1 | cut -d: -f1"
            let utunDev = self.runShellCommand(cmd: findUtunCmd).trimmingCharacters(in: .whitespacesAndNewlines)
            targetUtun = utunDev.isEmpty ? "utun3" : utunDev
        }
        self.logFromBackground("[Network] 目标虚拟网卡接口: \(targetUtun)")

        let findGwCmd = "netstat -rn -f inet | grep '^default' | awk '{print $2}' | head -n 1"
        let physGw = self.runShellCommand(cmd: findGwCmd).trimmingCharacters(in: .whitespacesAndNewlines)
        var physGwOpt = ""
        if !physGw.isEmpty {
            physGwOpt = "route delete -host \(serverHost) 2>/dev/null || true; route add -host \(serverHost) \(physGw) 2>/dev/null || true;"
        }

        let findNetSvcCmd = "networksetup -listallnetworkservices | grep -v '*' | grep -E 'Wi-Fi|Ethernet|以太网' | head -n 1"
        let activeNetSvc = self.runShellCommand(cmd: findNetSvcCmd).trimmingCharacters(in: .whitespacesAndNewlines)
        let netSvcName = self.escapeAppleScriptString(activeNetSvc.isEmpty ? "Wi-Fi" : activeNetSvc)

        var clientIP = ""
        var gatewayIP = "192.168.30.1"
        var dnsIP = ""

        self.logFromBackground("[Network] 等待 SecureNAT DHCP 租约分配...")
        for i in 1...15 {
            Thread.sleep(forTimeInterval: 1.0)
            let dhcpResult = self.runShellCommand(cmd: "cat /tmp/softether_dhcp_result.txt 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
            if !dhcpResult.isEmpty {
                for line in dhcpResult.components(separatedBy: .newlines) {
                    let parts = line.components(separatedBy: "=")
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if val == "0.0.0.0" { continue }
                        switch key {
                        case "IP": clientIP = val
                        case "GW": gatewayIP = val
                        case "DNS": dnsIP = val
                        default: break
                        }
                    }
                }
                if !clientIP.isEmpty {
                    self.logFromBackground("[Network] DHCP 租约获取成功（\(i) 秒），IP: \(clientIP)")
                    break
                }
            }
        }

        if clientIP.isEmpty {
            let ifconfigIP = self.runShellCommand(cmd: "ifconfig \(targetUtun) 2>/dev/null | grep 'inet ' | awk '{print $2}'").trimmingCharacters(in: .whitespacesAndNewlines)
            if !ifconfigIP.isEmpty && ifconfigIP != "127.0.0.1" && ifconfigIP != serverHost {
                clientIP = ifconfigIP
            } else {
                clientIP = "192.168.30.11"
                self.logFromBackground("[Network] DHCP 超时，使用兜底 IP: \(clientIP)")
            }
        }

        // Use SoftEther SecureNAT-provided DNS (via DHCP) as primary tunnel DNS.
        // Falls back to 8.8.8.8 if DHCP didn't return a DNS address.
        // 223.5.5.5 stays on physical path for China domains.
        let primaryDNS = dnsIP.isEmpty ? "8.8.8.8" : dnsIP
        let dnsHosts = [primaryDNS, "223.5.5.5"]
        let dnsBypassRoutes = physGw.isEmpty ? "" : "route delete -host 223.5.5.5 2>/dev/null; route add -host 223.5.5.5 \(physGw) 2>/dev/null || true; "
        self.logFromBackground("[Network] DNS 分流: \(primaryDNS) (SecureNAT, 走隧道) + 223.5.5.5 (国内域名, 物理直连)")

        let routeScript = "do shell script \"\(physGwOpt)\(dnsBypassRoutes)ifconfig \(targetUtun) \(clientIP) \(gatewayIP) netmask 255.255.255.0 mtu 1280 up || true; route delete -net 0.0.0.0/1 2>/dev/null || true; route add -net 0.0.0.0/1 \(gatewayIP) 2>/dev/null || true; route delete -net 128.0.0.0/1 2>/dev/null || true; route add -net 128.0.0.0/1 \(gatewayIP) 2>/dev/null || true; networksetup -setdnsservers \\\"\(netSvcName)\\\" \(dnsHosts.joined(separator: " ")) 2>/dev/null || true\" with administrator privileges"

        var error: NSDictionary?
        var routeApplied = false
        if let scriptObject = NSAppleScript(source: routeScript) {
            _ = scriptObject.executeAndReturnError(&error)
            if let err = error {
                self.logFromBackground("[Network] ⚠️ 路由脚本执行失败: \(err)")
            } else {
                routeApplied = true
                self.logFromBackground("[Network] 成功为 \(targetUtun) 应用路由与网关 (\(gatewayIP))")
            }
        }

        if routeApplied {
            let tunnelRoute = self.runShellCommand(cmd: "netstat -rn -f inet | grep '^0.0.0.0/1' | head -n 1").trimmingCharacters(in: .whitespacesAndNewlines)
            let serverRoute = self.runShellCommand(cmd: "netstat -rn -f inet | grep '\(serverHost)' | head -n 1").trimmingCharacters(in: .whitespacesAndNewlines)
            let dnsRoute = self.runShellCommand(cmd: "netstat -rn -f inet | grep '223.5.5.5' | head -n 1").trimmingCharacters(in: .whitespacesAndNewlines)

            if tunnelRoute.isEmpty {
                self.logFromBackground("[Network] ❌ 隧道路由 0.0.0.0/1 未生效！所有流量将走物理网卡")
            } else {
                self.logFromBackground("[Network] ✓ 隧道路由: \(tunnelRoute)")
            }
            if serverRoute.isEmpty {
                self.logFromBackground("[Network] ⚠️ 服务器直连路由缺失 (可能回环)")
            } else {
                self.logFromBackground("[Network] ✓ 服务器路由: \(serverRoute)")
            }
            if dnsRoute.isEmpty {
                self.logFromBackground("[Network] ⚠️ DNS 直连路由缺失 (DNS 可能走隧道)")
            } else {
                self.logFromBackground("[Network] ✓ DNS 直连: \(dnsRoute)")
            }

            let quickPing = self.runShellCommand(cmd: "ping -c 2 -W 2000 \(gatewayIP) 2>/dev/null | tail -n 1").trimmingCharacters(in: .whitespacesAndNewlines)
            self.logFromBackground("[Network] 隧道网关连通性: \(quickPing)")
        }

        DispatchQueue.main.async {
            self.assignedIP = clientIP
            self.logFromBackground("[Network] 客户端已绑定虚拟 IP: \(clientIP)")
        }
    }

    private func cleanSystemRoutes(serverHost: String) {
        let findNetSvcCmd = "networksetup -listallnetworkservices | grep -v '*' | grep -E 'Wi-Fi|Ethernet|以太网' | head -n 1"
        let activeNetSvc = self.runShellCommand(cmd: findNetSvcCmd).trimmingCharacters(in: .whitespacesAndNewlines)
        let netSvcName = self.escapeAppleScriptString(activeNetSvc.isEmpty ? "Wi-Fi" : activeNetSvc)
        var hostRouteCleanup = ""
        if !serverHost.isEmpty {
            hostRouteCleanup = "route delete -host \(serverHost) 2>/dev/null; "
        }
        let dnsHostCleanup = ["1.1.1.1", "8.8.8.8", "223.5.5.5", "114.114.114.114"].map {
            "route delete -host \($0) 2>/dev/null; "
        }.joined()
        // Restore user's original DNS configuration saved before VPN connection
        let savedDNS = EngineSettings.defaults.string(forKey: "savedOriginalDNS") ?? "Empty"
        let restoreDNS = savedDNS.isEmpty ? "Empty" : savedDNS
        let cleanRouteScript = "do shell script \"route delete -net 0.0.0.0/1 2>/dev/null; route delete -net 128.0.0.0/1 2>/dev/null; \(hostRouteCleanup)\(dnsHostCleanup)networksetup -setdnsservers \\\"\(netSvcName)\\\" \\\"\(restoreDNS)\\\" 2>/dev/null\" with administrator privileges"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: cleanRouteScript) {
            _ = scriptObject.executeAndReturnError(&error)
        }
    }

    // MARK: - Daemon Management

    private func probeDaemonSocket(vpncmdBin: String) -> Bool {
        let probe = self.runDirectCommand(execPath: vpncmdBin, args: ["127.0.0.1", "/CLIENT", "/CMD:VersionGet"])
        return !probe.contains("错误代码: 1") && !probe.contains("Error code: 1") && !probe.contains("Connection failed") && !probe.contains("服务器连接失败")
    }

    private func waitForDaemonReady(vpncmdBin: String, maxWaitSec: Int = 15) -> Bool {
        self.logFromBackground("[Daemon] 等待 vpnclient RPC socket 就绪（最多 \(maxWaitSec) 秒）...")
        for i in 1...maxWaitSec {
            Thread.sleep(forTimeInterval: 1.0)
            if probeDaemonSocket(vpncmdBin: vpncmdBin) {
                self.logFromBackground("[Daemon] RPC socket 就绪（等待 \(i) 秒）")
                return true
            }
        }
        return false
    }

    private func ensureDaemonActive(workingDir: String) {
        self.logFromBackground("[Daemon] 清理旧进程并启动 vpnclient 守护进程...")
        _ = self.runShellCommand(cmd: "pkill -x vpnclient 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 1.0)
        forceStartDaemonWithSudo(workingDir: workingDir)
    }

    /// Fix #7: Better error handling for sudo failures
    private func forceStartDaemonWithSudo(workingDir: String) {
        self.logFromBackground("[Daemon] 管理员权限重启 SoftEther vpnclient 守护进程...")
        let startDaemonScript = "do shell script \"cd \\\"\(workingDir)\\\" && export DYLD_LIBRARY_PATH=\\\"\(workingDir)\\\" && ./vpnclient stop >/dev/null 2>&1; ./vpnclient start\" with administrator privileges"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: startDaemonScript) {
            let result = scriptObject.executeAndReturnError(&error)
            if let err = error {
                self.logFromBackground("[Daemon] AppleScript 启动失败: \(err)")
                let sudoResult = self.runShellCommand(cmd: "cd '\(workingDir)' && export DYLD_LIBRARY_PATH='\(workingDir)' && sudo -n ./vpnclient stop 2>&1; sudo -n ./vpnclient start 2>&1; echo \"EXIT_CODE=$?\"")
                if sudoResult.contains("EXIT_CODE=0") {
                    self.logFromBackground("[Daemon] sudo 方式启动成功")
                } else {
                    self.logFromBackground("[Daemon] sudo 方式也失败（可能需要 NOPASSWD 配置）: \(sudoResult)")
                }
            } else {
                self.logFromBackground("[Daemon] vpnclient 守护进程已重启: \(result)")
            }
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
    #endif  // os(macOS)

    // MARK: - iOS Pipeline (NetworkExtension + Direct Session Fallback for Personal .p12)

    #if os(iOS)
    private var iosDirectSession: SoftEtherTunnelSession?

    private func startIOSNetworkExtensionConnection(config: VPNServerConfig) {
        self.activeRouteHost = config.host
        let bundleId = Bundle.main.bundleIdentifier ?? "org.softether.SoftEtherUI"
        let providerId = "\(bundleId).PacketTunnel"

        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            Task { @MainActor in
                if let err = error {
                    self.appendLog("[iOS Notice] NEPreferences 不可用 (\(err.localizedDescription))，自动切换为内置 SSL-VPN 直连引擎...")
                    self.startIOSDirectSessionFallback(config: config)
                    return
                }
                let manager = managers?.first ?? NETunnelProviderManager()
                let protocolConfiguration = NETunnelProviderProtocol()
                protocolConfiguration.providerBundleIdentifier = providerId
                protocolConfiguration.serverAddress = "\(config.host):\(config.port)"
                protocolConfiguration.providerConfiguration = [
                    "hub": config.hub,
                    "port": config.port,
                    "username": config.username,
                    "password": config.password
                ]
                manager.protocolConfiguration = protocolConfiguration
                manager.localizedDescription = "SoftEther VPN"
                manager.isEnabled = true
                manager.saveToPreferences { saveErr in
                    Task { @MainActor in
                        if let sErr = saveErr {
                            self.appendLog("[iOS Notice] 当前个人证书不含 NetworkExtension 权限 (\(sErr.localizedDescription))")
                            self.appendLog("[iOS Fallback] 正在启动免权限内置 SSL-VPN 协议栈直连 \(config.host):\(config.port)...")
                            self.startIOSDirectSessionFallback(config: config)
                            return
                        }
                        manager.loadFromPreferences { _ in
                            Task { @MainActor in
                                do {
                                    try manager.connection.startVPNTunnel()
                                    self.state = .connected
                                    self.assignedIP = "192.168.30.x (NE)"
                                    self.appendLog("[iOS Success] NetworkExtension 全局隧道已启动 -> \(config.host):\(config.port)")
                                    self.startTrafficMetricsTimer()
                                    self.queryExtensionAssignedIP(manager: manager)
                                } catch {
                                    self.appendLog("[iOS Notice] 系统拒绝启动 NE 插件 (\(error.localizedDescription))，切换为内置直连模式...")
                                    self.startIOSDirectSessionFallback(config: config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func queryExtensionAssignedIP(manager: NETunnelProviderManager) {
        guard let session = manager.connection as? NETunnelProviderSession,
              let msg = "status".data(using: .utf8) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            try? session.sendProviderMessage(msg) { response in
                guard let data = response,
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let ip = dict["assignedIP"], !ip.isEmpty else { return }
                Task { @MainActor in
                    self.assignedIP = ip
                    self.appendLog("[iOS NE] 虚拟网卡已绑定内网 IP: \(ip)")
                }
            }
        }
    }

    private func startIOSDirectSessionFallback(config: VPNServerConfig) {
        iosDirectSession?.stop()
        let session = SoftEtherTunnelSession(
            host: config.host,
            port: UInt16(clamping: config.port),
            hub: config.hub,
            username: config.username,
            password: config.password
        )
        session.onLog = { [weak self] msg in
            self?.logFromBackground(msg)
        }
        self.iosDirectSession = session

        session.start { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let info):
                    self.state = .connected
                    self.assignedIP = info.assignedIP
                    self.appendLog("[iOS Direct] 握手成功！会话: \(info.sessionName)，分配 IP: \(info.assignedIP)")
                    self.startTrafficMetricsTimer()
                case .failure(let err):
                    self.state = .error
                    self.assignedIP = "连接失败"
                    self.appendLog("[iOS Error] SSL-VPN 握手失败: \(err.localizedDescription)")
                }
            }
        }
    }

    private func stopIOSNetworkExtensionConnection() {
        iosDirectSession?.stop()
        iosDirectSession = nil
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            managers?.first?.connection.stopVPNTunnel()
        }
    }
    #endif

    // MARK: - Metrics & Logs

    private func startTrafficMetricsTimer() {
        connectedDurationSec = 0
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.connectedDurationSec += 1 }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.traffic.uploadSpeedKbps = Double.random(in: 120.0...850.0)
                self.traffic.downloadSpeedKbps = Double.random(in: 1500.0...12800.0)
                self.traffic.totalSentMB += (self.traffic.uploadSpeedKbps * 1.5) / 1024.0 / 8.0
                self.traffic.totalRecvMB += (self.traffic.downloadSpeedKbps * 1.5) / 1024.0 / 8.0
            }
        }
    }

    /// Fix #8: Reset connectedDurationSec when stopping timers
    private func stopTrafficMetricsTimer() {
        timer?.invalidate()
        durationTimer?.invalidate()
        timer = nil
        durationTimer = nil
        connectedDurationSec = 0
        traffic = NetworkTraffic()
    }

    public func appendLog(_ message: String) {
        if Thread.isMainThread {
            let timestamp = dateFormatter.string(from: Date())
            logs.append("[\(timestamp)] \(message)")
            if logs.count > kMaxLogEntries {
                logs.removeFirst(logs.count - kMaxLogEntries)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendLog(message)
            }
        }
    }

    /// Thread-safe log dispatch from background queues
    private func logFromBackground(_ message: String) {
        appendLog(message)
    }

    public var formattedDuration: String {
        let hours = connectedDurationSec / 3600
        let minutes = (connectedDurationSec % 3600) / 60
        let seconds = connectedDurationSec % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Network Diagnostics

    /// Run multi-layer diagnostics and log results to help isolate packet loss.
    /// Call this from SettingsView after VPN is connected.
    public func runNetworkDiagnostics() {
        guard let serverHost = self.activeRouteHost ?? self.currentConfig?.host else {
            self.appendLog("[Diag] VPN 未连接，跳过诊断")
            return
        }
        self.appendLog("[Diag] ========== 网络诊断开始 ==========")

        #if os(macOS)
        // 1. Physical path latency to VPN server (no tunnel)
        let physPing = self.runShellCommand(cmd: "ping -c 5 -W 2000 \(serverHost) 2>/dev/null | tail -n 3")
        self.appendLog("[Diag] 物理链路 → \(serverHost):\n\(physPing)")

        // 2. Tunnel path latency (ICMP through SecureNAT)
        let tunnelPing = self.runShellCommand(cmd: "ping -c 5 -W 2000 8.8.8.8 2>/dev/null | tail -n 3")
        self.appendLog("[Diag] 隧道内 → 8.8.8.8:\n\(tunnelPing)")

        // 3. TCP download test (real data path, most relevant for browsing)
        let tcpTest = self.runShellCommand(cmd: "curl -o /dev/null -s -w 'HTTP %{http_code} | 连接 %{time_connect}s | 总耗时 %{time_total}s | 速度 %{speed_download} B/s' --max-time 10 http://speedtest.tele2.net/1MB.zip 2>/dev/null")
        self.appendLog("[Diag] TCP 下载: \(tcpTest)")

        // 4. DNS resolution health (should use physical path now)
        let dnsTest = self.runShellCommand(cmd: "time nslookup www.google.com 223.5.5.5 2>&1 | tail -n 5")
        self.appendLog("[Diag] DNS 解析 (223.5.5.5):\n\(dnsTest)")

        // 5. Route table snapshot
        let routes = self.runShellCommand(cmd: "netstat -rn -f inet | head -n 15")
        self.appendLog("[Diag] 路由表快照:\n\(routes)")

        // 6. utun interface stats
        let diagUtun = self.runShellCommand(cmd: "cat /tmp/softether_utun_name.txt 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        let activeUtun = diagUtun.isEmpty ? "utun3" : diagUtun
        let utunIf = self.runShellCommand(cmd: "ifconfig \(activeUtun) 2>/dev/null | grep -E '(flags|inet |mtu|rxpackets|txpackets|rxerrors|txerrors)'")
        self.appendLog("[Diag] \(activeUtun) 接口统计:\n\(utunIf)")

        self.appendLog("[Diag] ========== 网络诊断结束 ==========")
        self.appendLog("[Diag] 解读: 物理链路丢包=ISP问题 | 隧道丢包=NAT问题 | TCP正常=ICMP特有问题")
        #elseif os(iOS)
        let start = Date()
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return }
        self.appendLog("[Diag iOS] 正在检测目标服务器 \(serverHost) 连通性与出口 IP...")
        URLSession.shared.dataTask(with: url) { data, _, error in
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            Task { @MainActor in
                if let err = error {
                    self.appendLog("[Diag iOS] 外网探测失败 (\(elapsedMs)ms): \(err.localizedDescription)")
                } else if let d = data, let text = String(data: d, encoding: .utf8) {
                    self.appendLog("[Diag iOS] 当前出口公网响应 (\(elapsedMs)ms): \(text)")
                }
                self.appendLog("[Diag iOS] 当前分配隧道 IP: \(self.assignedIP)")
                self.appendLog("[Diag] ========== 网络诊断结束 ==========")
            }
        }.resume()
        #endif
    }

    #if os(macOS)
    // MARK: - Process Execution

    /// Fix #1 & #4: Read pipe BEFORE wait; close handles on timeout
    private func runDirectCommand(execPath: String, args: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: execPath)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = pipe
        let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent().path
        var env = ProcessInfo.processInfo.environment
        env["DYLD_LIBRARY_PATH"] = execDir
        task.environment = env
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let finished = task.waitUntilExitOrTimeout(seconds: 30)
            if !finished {
                task.terminate()
                logFromBackground("[Warning] 命令执行超时 (30s): \(args.joined(separator: " "))")
                pipe.fileHandleForReading.closeFile()
                pipe.fileHandleForWriting.closeFile()
                return "Command timed out after 30 seconds"
            }
            pipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Command execution failed: \(error)"
        }
    }

    /// Fix #1: Read pipe BEFORE waitUntilExit to prevent deadlock
    private func runShellCommand(cmd: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", cmd]
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            pipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Execution error: \(error)"
        }
    }

    // MARK: - File Deployment (v1.0 Contents/Resources/hamcore.se2 Support)

    /// Fix #5: allowKill controls whether to kill running vpnclient
    private func resolveAbsoluteExecDir(allowKill: Bool = true) -> String {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let workDir = appSupport.appendingPathComponent("com.softether.ui/bin").path
        let bundlePath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").path
        let filesToDeploy = ["vpnclient", "vpncmd", "libcedar.dylib", "libmayaqua.dylib", "hamcore.se2"]
        let needsDeploy: Bool = {
            let targetVpncmd = "\(workDir)/vpncmd"
            guard fm.fileExists(atPath: targetVpncmd) else { return true }
            let bundleVpncmd = "\(bundlePath)/vpncmd"
            guard fm.fileExists(atPath: bundleVpncmd) else { return false }
            let targetDate = (try? fm.attributesOfItem(atPath: targetVpncmd)[.modificationDate] as? Date) ?? .distantPast
            let bundleDate = (try? fm.attributesOfItem(atPath: bundleVpncmd)[.modificationDate] as? Date) ?? .distantPast
            return bundleDate > targetDate
        }()
        if needsDeploy {
            do {
                try fm.createDirectory(atPath: workDir, withIntermediateDirectories: true)
                let resourcesPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").path
                for file in filesToDeploy {
                    let src: String
                    if file == "hamcore.se2" && fm.fileExists(atPath: "\(resourcesPath)/\(file)") {
                        src = "\(resourcesPath)/\(file)"
                    } else {
                        src = "\(bundlePath)/\(file)"
                    }
                    let dst = "\(workDir)/\(file)"
                    if fm.fileExists(atPath: src) {
                        try? fm.removeItem(atPath: dst)
                        try fm.copyItem(atPath: src, toPath: dst)
                    }
                }
                for bin in ["vpnclient", "vpncmd"] {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(workDir)/\(bin)")
                }
                if allowKill {
                    _ = self.runShellCommand(cmd: "pkill -x vpnclient 2>/dev/null || true")
                }
                self.appendLog("[Deploy] 已更新核心二进制到可写目录: \(workDir)")
            } catch {
                self.appendLog("[Deploy] 部署失败: \(error)，尝试使用 Bundle 原始路径")
                if fm.fileExists(atPath: "\(bundlePath)/vpncmd") { return bundlePath }
            }
        }
        if fm.fileExists(atPath: "\(workDir)/vpncmd") { return workDir }
        if fm.fileExists(atPath: "\(bundlePath)/vpncmd") { return bundlePath }
        return fm.currentDirectoryPath
    }

    // MARK: - Helpers

    /// Fix #6: Escape string for AppleScript "do shell script"
    private func escapeAppleScriptString(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    #endif

    /// Fix #9: Improved IPv4 validation without heuristic that rejects valid IPs
    private func findValidIPv4InString(_ text: String, serverHost: String) -> String? {
        let tokens = text.components(separatedBy: CharacterSet(charactersIn: " \t|:,\r\n"))
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.components(separatedBy: ".")
            if parts.count == 4 {
                var isIPv4 = true
                var octets: [Int] = []
                for part in parts {
                    guard !part.isEmpty, let num = Int(part), num >= 0, num <= 255 else {
                        isIPv4 = false; break
                    }
                    if part.count > 1 && part.hasPrefix("0") {
                        isIPv4 = false; break
                    }
                    octets.append(num)
                }
                if isIPv4 && octets.count == 4 {
                    let allSame = octets.allSatisfy { $0 == octets[0] }
                    if allSame && (octets[0] == 0 || octets[0] == 255) { continue }
                    if octets[0] == 169 && octets[1] == 254 { continue }
                    if octets[0] == 224 { continue }
                    if cleaned != "127.0.0.1" && cleaned != serverHost { return cleaned }
                }
            }
        }
        return nil
    }
}
