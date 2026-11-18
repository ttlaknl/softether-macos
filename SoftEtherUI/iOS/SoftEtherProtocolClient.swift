// SoftEtherProtocolClient.swift
// Pure Swift SoftEther SSL-VPN Wire Protocol + L2/L3 Ethernet-IP Bridge (ARM64 iOS & macOS)
// Implements:
//   1. SoftEther SHA-0 (MY_SHA0_hash) for HashPassword & SecurePassword
//   2. SoftEther Binary PACK Serializer / Deserializer
//   3. HTTP Watermark Handshake (/vpnsvc/connect.cgi -> Hello -> /vpnsvc/vpn.cgi -> Welcome)
//   4. SoftEther TCP Data Block Framing + KeepAlive (0xFFFFFFFF)
//   5. L2 Ethernet <-> L3 IPv4 Translation + Built-in DHCP & ARP Responder for SecureNAT

import Foundation
import Network
import Security
import Darwin

// MARK: - 1. SoftEther SHA-0 Implementation (Ported from Mayaqua/Encrypt.c)

public enum SoftEtherSHA0 {
    @inline(__always)
    private static func rol(_ bits: UInt32, _ value: UInt32) -> UInt32 {
        return (value << bits) | (value >> (32 - bits))
    }

    /// Compute 20-byte SHA-0 digest (no 1-bit rotation in W[16..79] expansion, matching SoftEther Sha0)
    public static func hash(_ data: Data) -> Data {
        var state: [UInt32] = [
            0x67452301,
            0xEFCDAB89,
            0x98BADCFE,
            0x10325476,
            0xC3D2E1F0
        ]

        var msg = [UInt8](data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while (msg.count % 64) != 56 {
            msg.append(0x00)
        }
        for i in 0..<8 {
            msg.append(UInt8((bitLen >> ((7 - i) * 8)) & 0xFF))
        }

        var w = [UInt32](repeating: 0, count: 80)
        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            for t in 0..<16 {
                let idx = chunkStart + t * 4
                w[t] = (UInt32(msg[idx]) << 24)
                     | (UInt32(msg[idx + 1]) << 16)
                     | (UInt32(msg[idx + 2]) << 8)
                     | UInt32(msg[idx + 3])
            }
            for t in 16..<80 {
                // SHA-0: NO rol(1, ...) here (matches Encrypt.c line 4772)
                w[t] = w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16]
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]

            for t in 0..<80 {
                var tmp = rol(5, a) &+ e &+ w[t]
                if t < 20 {
                    tmp = tmp &+ ((d ^ (b & (c ^ d))) &+ 0x5A827999)
                } else if t < 40 {
                    tmp = tmp &+ ((b ^ c ^ d) &+ 0x6ED9EBA1)
                } else if t < 60 {
                    tmp = tmp &+ (((b & c) | (d & (b | c))) &+ 0x8F1BBCDC)
                } else {
                    tmp = tmp &+ ((b ^ c ^ d) &+ 0xCA62C1D6)
                }
                e = d
                d = c
                c = rol(30, b)
                b = a
                a = tmp
            }

            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
        }

        var out = Data(capacity: 20)
        for s in state {
            out.append(UInt8((s >> 24) & 0xFF))
            out.append(UInt8((s >> 16) & 0xFF))
            out.append(UInt8((s >> 8) & 0xFF))
            out.append(UInt8(s & 0xFF))
        }
        return out
    }

    /// Account.c: HashPassword(dst, username, password) = Sha0(password + UPPER(username))
    public static func hashPassword(username: String, password: String) -> Data {
        var buf = Data()
        buf.append(contentsOf: password.utf8)
        buf.append(contentsOf: username.uppercased().utf8)
        return hash(buf)
    }

    /// Sam.c: SecurePassword(secure_password, password_hash, random) = Sha0(password_hash + random)
    public static func securePassword(hashedPassword: Data, serverRandom: Data) -> Data {
        var buf = Data()
        buf.append(hashedPassword)
        buf.append(serverRandom)
        return hash(buf)
    }
}

// MARK: - 2. SoftEther Binary PACK Codec (Ported from Mayaqua/Pack.c)

public struct SoftEtherPack {
    public enum ValueType: UInt32 {
        case int = 0
        case data = 1
        case str = 2
        case unistr = 3
        case int64 = 4
    }

    public enum ElementValue {
        case int(UInt32)
        case int64(UInt64)
        case data(Data)
        case str(String)
        case unistr(String)

        var valueType: ValueType {
            switch self {
            case .int: return .int
            case .int64: return .int64
            case .data: return .data
            case .str: return .str
            case .unistr: return .unistr
            }
        }
    }

    private struct Element {
        var name: String
        var type: ValueType
        var values: [ElementValue]
    }

    private var elements: [Element] = []

    public init() {}

    public mutating func addStr(_ name: String, _ value: String) {
        elements.append(Element(name: name, type: .str, values: [.str(value)]))
    }

    public mutating func addInt(_ name: String, _ value: UInt32) {
        elements.append(Element(name: name, type: .int, values: [.int(value)]))
    }

    public mutating func addBool(_ name: String, _ value: Bool) {
        addInt(name, value ? 1 : 0)
    }

    public mutating func addData(_ name: String, _ value: Data) {
        elements.append(Element(name: name, type: .data, values: [.data(value)]))
    }

    public func getInt(_ name: String) -> UInt32? {
        guard let el = elements.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let first = el.values.first else { return nil }
        if case .int(let v) = first { return v }
        return nil
    }

    public func getStr(_ name: String) -> String? {
        guard let el = elements.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let first = el.values.first else { return nil }
        switch first {
        case .str(let s), .unistr(let s): return s
        default: return nil
        }
    }

    public func getData(_ name: String) -> Data? {
        guard let el = elements.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let first = el.values.first else { return nil }
        if case .data(let d) = first { return d }
        return nil
    }

    public func serialize() -> Data {
        var out = Data()
        out.appendBEUInt32(UInt32(elements.count))
        for el in elements {
            // WriteBufStr: writes (len + 1) followed by len bytes
            let nameBytes = [UInt8](el.name.utf8)
            out.appendBEUInt32(UInt32(nameBytes.count + 1))
            out.append(contentsOf: nameBytes)
            out.appendBEUInt32(el.type.rawValue)
            out.appendBEUInt32(UInt32(el.values.count))
            for val in el.values {
                switch val {
                case .int(let v):
                    out.appendBEUInt32(v)
                case .int64(let v):
                    out.appendBEUInt64(v)
                case .data(let d):
                    out.appendBEUInt32(UInt32(d.count))
                    out.append(d)
                case .str(let s):
                    let sBytes = [UInt8](s.utf8)
                    out.appendBEUInt32(UInt32(sBytes.count))
                    out.append(contentsOf: sBytes)
                case .unistr(let s):
                    var uBytes = [UInt8](s.utf8)
                    uBytes.append(0)
                    out.appendBEUInt32(UInt32(uBytes.count))
                    out.append(contentsOf: uBytes)
                }
            }
        }
        return out
    }

    public static func deserialize(from data: Data) -> SoftEtherPack? {
        var offset = 0
        guard let numElements = data.readBEUInt32(at: &offset), numElements <= 4096 else {
            return nil
        }
        var pack = SoftEtherPack()
        for _ in 0..<numElements {
            // ReadBufStr: reads len, if len == 0 fail, actual string length is (len - 1)
            guard let rawNameLen = data.readBEUInt32(at: &offset), rawNameLen >= 1 else {
                return nil
            }
            let nameLen = Int(rawNameLen - 1)
            guard offset + nameLen <= data.count else { return nil }
            let name = String(decoding: data[offset..<(offset + nameLen)], as: UTF8.self)
            offset += nameLen

            guard let rawType = data.readBEUInt32(at: &offset),
                  let type = ValueType(rawValue: rawType),
                  let numValues = data.readBEUInt32(at: &offset),
                  numValues <= 65536 else {
                return nil
            }

            var vals: [ElementValue] = []
            for _ in 0..<numValues {
                switch type {
                case .int:
                    guard let v = data.readBEUInt32(at: &offset) else { return nil }
                    vals.append(.int(v))
                case .int64:
                    guard let v = data.readBEUInt64(at: &offset) else { return nil }
                    vals.append(.int64(v))
                case .data:
                    guard let sz = data.readBEUInt32(at: &offset),
                          offset + Int(sz) <= data.count else { return nil }
                    let sub = Data(data[offset..<(offset + Int(sz))])
                    offset += Int(sz)
                    vals.append(.data(sub))
                case .str:
                    guard let sz = data.readBEUInt32(at: &offset),
                          offset + Int(sz) <= data.count else { return nil }
                    let s = String(decoding: data[offset..<(offset + Int(sz))], as: UTF8.self)
                    offset += Int(sz)
                    vals.append(.str(s))
                case .unistr:
                    guard let sz = data.readBEUInt32(at: &offset),
                          offset + Int(sz) <= data.count else { return nil }
                    var rawSlice = data[offset..<(offset + Int(sz))]
                    if rawSlice.last == 0 { rawSlice = rawSlice.dropLast() }
                    let s = String(decoding: rawSlice, as: UTF8.self)
                    offset += Int(sz)
                    vals.append(.unistr(s))
                }
            }
            pack.elements.append(Element(name: name, type: type, values: vals))
        }
        return pack
    }
}

// MARK: - 3. SoftEther SSL-VPN Session & L2/L3 Bridge

public final class SoftEtherTunnelSession {
    public struct HandshakeResult {
        public let sessionName: String
        public let assignedIP: String
        public let subnetMask: String
        public let gatewayIP: String
        public let dnsServers: [String]
    }

    private let host: String
    private let port: UInt16
    private let hub: String
    private let username: String
    private let password: String

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.softether.ios.session", qos: .userInitiated)
    private let stopLock = NSLock()
    private let statsLock = NSLock()
    private var _isStopped = false
    private var isStopped: Bool {
        get { stopLock.lock(); defer { stopLock.unlock() }; return _isStopped }
        set { stopLock.lock(); defer { stopLock.unlock() }; _isStopped = newValue }
    }
    private var rxBuffer = Data()
    private var isRunning = false
    private var disconnectNotified = false
    private var keepAliveTimer: DispatchSourceTimer?
    private var keepAliveTickCount: UInt64 = 0
    private var handshakeTimeoutWork: DispatchWorkItem?
    private var pendingHandshake: (sessionName: String, completion: (Result<HandshakeResult, Error>) -> Void)?

    // Virtual L2 Adapter MAC & Learned Gateway MAC
    private let myMAC: [UInt8]
    private var gatewayMAC: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
    private var assignedIPBytes: [UInt8] = [192, 168, 30, 18]
    private var gatewayIPBytes: [UInt8] = [192, 168, 30, 1]
    private var subnetMaskBytes: [UInt8] = [255, 255, 255, 0]
    private var negotiatedDNSServers: [String] = ["8.8.8.8", "1.1.1.1"]
    private var dhcpCompleted = false
    private let dhcpXid: UInt32 = UInt32.random(in: 1...0x7FFFFFFF)

    public var onInboundIPPacket: ((Data) -> Void)?
    public var onInboundIPPackets: (([Data]) -> Void)?
    public var onDisconnect: ((Error?) -> Void)?
    public var onLog: ((String) -> Void)?
    private var _totalBytesSent: UInt64 = 0
    private var _totalBytesRecv: UInt64 = 0
    public var totalBytesSent: UInt64 {
        statsLock.lock(); defer { statsLock.unlock() }; return _totalBytesSent
    }
    public var totalBytesRecv: UInt64 {
        statsLock.lock(); defer { statsLock.unlock() }; return _totalBytesRecv
    }

    private func addBytesSent(_ count: Int) {
        statsLock.lock()
        _totalBytesSent += UInt64(count)
        statsLock.unlock()
    }

    private func addBytesRecv(_ count: Int) {
        statsLock.lock()
        _totalBytesRecv += UInt64(count)
        statsLock.unlock()
    }

    public static func resolveIPv4(host: String) -> String? {
        var inAddr = in_addr()
        if inet_pton(AF_INET, host, &inAddr) == 1 {
            return host
        }
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(first) }
        if let sa = first.pointee.ai_addr {
            var sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                return String(cString: buf)
            }
        }
        return nil
    }

    public init(host: String, port: UInt16, hub: String, username: String, password: String) {
        self.host = host
        self.port = port
        self.hub = hub
        self.username = username
        self.password = password
        self.myMAC = [
            0x5E,
            UInt8.random(in: 0x10...0xFE),
            UInt8.random(in: 0x10...0xFE),
            UInt8.random(in: 0x10...0xFE),
            UInt8.random(in: 0x10...0xFE),
            UInt8.random(in: 0x10...0xFE)
        ]
    }

    public func start(completion: @escaping (Result<HandshakeResult, Error>) -> Void) {
        isStopped = false
        disconnectNotified = false
        keepAliveTickCount = 0
        dhcpCompleted = false

        let tlsOptions = NWProtocolTLS.Options()
        let secOpts = tlsOptions.securityProtocolOptions
        // iOS 13+ API (tls_protocol_version_t). The old sec_protocol_options_set_tls_min_version
        // with SSLProtocol is deprecated and its `.TLSv12` member no longer exists in iOS 26 SDK.
        sec_protocol_options_set_min_tls_protocol_version(secOpts, .TLSv12)
        sec_protocol_options_set_verify_block(secOpts, { _, _, complete in
            complete(true) // SoftEther servers use self-signed certificates by default
        }, queue)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(Self.makeError("无效端口: \(port)")))
            return
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        self.connection = conn

        var handshakeCompletedOrFailed = false
        var handshakeEntered = false

        let completeOnce: (Result<HandshakeResult, Error>) -> Void = { [weak self] result in
            self?.handshakeTimeoutWork?.cancel()
            self?.handshakeTimeoutWork = nil
            guard !handshakeCompletedOrFailed else { return }
            handshakeCompletedOrFailed = true
            completion(result)
        }

        let timeoutWork = DispatchWorkItem { [weak self, weak conn] in
            guard let self = self, !self.isStopped, !handshakeCompletedOrFailed else { return }
            handshakeCompletedOrFailed = true
            self.isRunning = false
            conn?.cancel()
            if self.connection === conn {
                self.connection = nil
            }
            completion(.failure(Self.makeError("SSL-VPN 握手超时")))
        }
        handshakeTimeoutWork?.cancel()
        handshakeTimeoutWork = timeoutWork
        queue.asyncAfter(deadline: .now() + 12.0, execute: timeoutWork)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.isStopped else { return }
            switch state {
            case .ready:
                guard !handshakeEntered else { return }
                handshakeEntered = true
                self.log("[TLS] 已建立到 \(self.host):\(self.port) 的加密通道")
                self.performWatermarkAndAuth(completion: completeOnce)
            case .failed(let err):
                if !handshakeCompletedOrFailed {
                    completeOnce(.failure(err))
                } else if self.isRunning {
                    self.triggerDisconnect(err)
                }
            case .cancelled:
                if self.isRunning && !self.isStopped {
                    self.triggerDisconnect(nil)
                }
            default:
                break
            }
        }

        conn.viabilityUpdateHandler = { [weak self] isViable in
            guard let self = self, !self.isStopped, self.isRunning else { return }
            if !isViable {
                self.log("[NW] 链路连通性暂时不可用，等待恢复或重连...")
            }
        }

        conn.start(queue: queue)
    }

    public func stop() {
        isStopped = true
        queue.async { [weak self] in
            guard let self = self else { return }
            self.handshakeTimeoutWork?.cancel()
            self.handshakeTimeoutWork = nil
            self.isRunning = false
            self.pendingHandshake = nil
            self.rxBuffer = Data()
            self.keepAliveTimer?.cancel()
            self.keepAliveTimer = nil
            self.connection?.cancel()
            self.connection = nil
        }
    }

    private func triggerDisconnect(_ error: Error?) {
        guard !isStopped, !disconnectNotified else { return }
        disconnectNotified = true
        isRunning = false
        pendingHandshake = nil
        handshakeTimeoutWork?.cancel()
        handshakeTimeoutWork = nil
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        rxBuffer = Data()
        connection?.cancel()
        connection = nil
        onDisconnect?(error)
    }

    // MARK: - SoftEther Handshake (Signature -> Hello -> Auth -> Welcome)

    private func performWatermarkAndAuth(completion: @escaping (Result<HandshakeResult, Error>) -> Void) {
        // 1. Upload Signature (POST /vpnsvc/connect.cgi with "VPNCONNECT")
        let signatureBody = Data("VPNCONNECT".utf8)
        let sigReq = "POST /vpnsvc/connect.cgi HTTP/1.1\r\n"
                   + "Host: \(host)\r\n"
                   + "Content-Type: image/jpeg\r\n"
                   + "Connection: Keep-Alive\r\n"
                   + "Content-Length: \(signatureBody.count)\r\n\r\n"
        var payload = Data(sigReq.utf8)
        payload.append(signatureBody)

        sendRaw(payload) { [weak self] err in
            guard let self = self else { return }
            if let err = err {
                completion(.failure(err))
                return
            }

            // 2. Receive Hello Pack
            self.receiveHTTPPack { result in
                switch result {
                case .failure(let err):
                    completion(.failure(err))
                case .success(let helloPack):
                    guard let random = helloPack.getData("random"), random.count == 20 else {
                        let srvErr = helloPack.getInt("error") ?? 999
                        completion(.failure(Self.makeError("服务端未返回 Hello Random (Error=\(srvErr))")))
                        return
                    }
                    let srvStr = helloPack.getStr("hello") ?? "SoftEther VPN Server"
                    self.log("[Hello] 收到服务端握手: \(srvStr)")
                    self.sendLoginAuthPack(serverRandom: random, completion: completion)
                }
            }
        }
    }

    private func sendLoginAuthPack(serverRandom: Data, completion: @escaping (Result<HandshakeResult, Error>) -> Void) {
        let hashedPw = SoftEtherSHA0.hashPassword(username: username, password: password)
        let securePw = SoftEtherSHA0.securePassword(hashedPassword: hashedPw, serverRandom: serverRandom)

        var authPack = SoftEtherPack()
        authPack.addStr("method", "login")
        authPack.addStr("hubname", hub)
        authPack.addStr("username", username)
        authPack.addInt("authtype", 1) // CLIENT_AUTHTYPE_PASSWORD
        authPack.addData("secure_password", securePw)
        authPack.addInt("protocol", 0) // CONNECTION_TCP
        authPack.addStr("hello", "SoftEther VPN Client")
        authPack.addInt("version", 444)
        authPack.addInt("build", 9807)
        authPack.addStr("client_str", "SoftEther VPN Client (iOS ARM64)")
        authPack.addInt("client_ver", 444)
        authPack.addInt("client_build", 9807)
        authPack.addInt("max_connection", 1)
        authPack.addInt("use_encrypt", 1)
        authPack.addInt("use_compress", 0)
        authPack.addInt("half_connection", 0)
        authPack.addBool("require_bridge_routing_mode", false)
        authPack.addBool("require_monitor_mode", false)
        authPack.addBool("qos", false)
        authPack.addData("unique_id", SoftEtherSHA0.hash(Data(myMAC)))

        let packData = authPack.serialize()
        let httpHeader = "POST /vpnsvc/vpn.cgi HTTP/1.1\r\n"
                       + "Host: \(host)\r\n"
                       + "Keep-Alive: timeout=15, max=19\r\n"
                       + "Connection: Keep-Alive\r\n"
                       + "Content-Type: application/octet-stream\r\n"
                       + "Content-Length: \(packData.count)\r\n\r\n"
        var req = Data(httpHeader.utf8)
        req.append(packData)

        sendRaw(req) { [weak self] err in
            guard let self = self else { return }
            if let err = err {
                completion(.failure(err))
                return
            }

            // 4. Receive Welcome Pack
            self.receiveHTTPPack { result in
                switch result {
                case .failure(let err):
                    completion(.failure(err))
                case .success(let welcomePack):
                    if let errCode = welcomePack.getInt("error"), errCode != 0 {
                        completion(.failure(Self.makeError("SoftEther 认证失败，错误代码: \(errCode)")))
                        return
                    }
                    let sessionName = welcomePack.getStr("session_name") ?? "SID-IOS-ARM64"
                    guard !self.isStopped else { return }
                    self.log("[Welcome] 认证成功！会话已建立: \(sessionName)")

                    self.isRunning = true
                    self.pendingHandshake = (sessionName: sessionName, completion: completion)
                    self.sendKeepAlivePacket()
                    self.startKeepAliveTimer()
                    self.startDataStreamLoop()

                    // Trigger DHCP Discover + ARP probe for SecureNAT gateway (192.168.30.1)
                    self.sendDHCPDiscover()
                    self.sendARPRequest(targetIP: self.gatewayIPBytes)

                    // Wait up to 2.5s for SecureNAT DHCP Offer, or complete with 192.168.30.18 fallback
                    self.queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                        self?.completePendingHandshakeIfNeeded()
                    }
                }
            }
        }
    }

    // MARK: - L3 IPv4 -> L2 Ethernet Encapsulation

    public func sendIPv4Packet(_ ipPacket: Data) {
        sendIPv4Packets([ipPacket])
    }

    public func sendIPv4Packets(_ ipPackets: [Data]) {
        guard !ipPackets.isEmpty else { return }
        queue.async { [weak self] in
            guard let self = self, self.isRunning, !self.isStopped else { return }

            var frames: [Data] = []
            frames.reserveCapacity(ipPackets.count)

            for ipPacket in ipPackets {
                guard ipPacket.count >= 20 else { continue }
                let version = (ipPacket[ipPacket.startIndex] >> 4) & 0x0F
                guard version == 4 else { continue }

                var ethFrame = Data(capacity: 14 + ipPacket.count)
                ethFrame.append(contentsOf: self.gatewayMAC) // Destination MAC (SecureNAT Gateway)
                ethFrame.append(contentsOf: self.myMAC)      // Source MAC
                ethFrame.append(contentsOf: [0x08, 0x00])    // EtherType: IPv4
                ethFrame.append(ipPacket)
                frames.append(ethFrame)
            }

            guard !frames.isEmpty else { return }
            self.sendEthernetFrames(frames)
        }
    }

    private func sendEthernetFrame(_ frame: Data) {
        sendEthernetFrames([frame])
    }

    private func sendEthernetFrames(_ frames: [Data]) {
        guard isRunning, !isStopped, !frames.isEmpty else { return }
        let totalSize = 4 + frames.reduce(0) { $0 + 4 + $1.count }
        var blockStream = Data(capacity: totalSize)
        blockStream.appendBEUInt32(UInt32(frames.count))
        for frame in frames {
            blockStream.appendBEUInt32(UInt32(frame.count))
            blockStream.append(frame)
        }
        addBytesSent(blockStream.count)
        sendRaw(blockStream) { [weak self] err in
            guard let self = self, let err = err else { return }
            self.queue.async {
                if self.isRunning && !self.isStopped {
                    self.log("[Error] 发送数据帧失败: \(err.localizedDescription)")
                    self.triggerDisconnect(err)
                }
            }
        }
    }

    // MARK: - Inbound SoftEther Stream & L2 -> L3 Decapsulation

    private func startDataStreamLoop() {
        guard isRunning, !isStopped, let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            guard !self.isStopped, self.isRunning else { return }

            if let d = data, !d.isEmpty {
                self.addBytesRecv(d.count)
                self.rxBuffer.append(d)
                self.processRxStreamBuffer()
            }
            if isComplete || error != nil {
                if let err = error {
                    self.log("[Disconnect] 通道接收中断: \(err.localizedDescription)")
                } else {
                    self.log("[Disconnect] 服务端关闭了数据流 (EOF)")
                }
                self.triggerDisconnect(error)
                return
            }
            if self.isRunning && !self.isStopped {
                self.startDataStreamLoop()
            }
        }
    }

    private func processRxStreamBuffer() {
        var inboundBatch: [Data] = []

        while rxBuffer.count >= 4 {
            var offset = 0
            guard let numBlocks = rxBuffer.readBEUInt32(at: &offset) else { break }

            // SoftEther allows 4-byte 0-block keepalive/flush marker (NextBlockNum == 0)
            if numBlocks == 0 {
                rxBuffer.removeFirst(4)
                continue
            }

            if numBlocks == 0xFFFFFFFF {
                // KEEP_ALIVE_MAGIC requires 4-byte magic + 4-byte size + kaSize payload
                guard rxBuffer.count >= 8 else { break }
                guard let kaSize = rxBuffer.readBEUInt32(at: &offset) else { break }
                guard kaSize <= 65536 else {
                    log("[Error] SoftEther KeepAlive 长度异常 (\(kaSize))，重置会话")
                    rxBuffer = Data()
                    triggerDisconnect(Self.makeError("KeepAlive 帧异常"))
                    return
                }
                guard rxBuffer.count >= 8 + Int(kaSize) else { break }
                rxBuffer.removeSubrange(0..<(8 + Int(kaSize)))
                continue
            }

            guard numBlocks <= 4096 else {
                log("[Error] SoftEther 数据块数量异常 (\(numBlocks))，重置会话")
                rxBuffer = Data()
                triggerDisconnect(Self.makeError("协议帧同步异常"))
                return
            }

            var tempOffset = offset
            var frames: [Data] = []
            frames.reserveCapacity(Int(numBlocks))
            var completeBatch = true

            for _ in 0..<numBlocks {
                guard let blockSize = rxBuffer.readBEUInt32(at: &tempOffset) else {
                    completeBatch = false
                    break
                }
                guard blockSize <= 65536 else {
                    log("[Error] SoftEther 单帧长度异常 (\(blockSize))，重置会话")
                    rxBuffer = Data()
                    triggerDisconnect(Self.makeError("数据帧长度越界"))
                    return
                }
                guard tempOffset + Int(blockSize) <= rxBuffer.count else {
                    completeBatch = false
                    break
                }
                let frame = Data(rxBuffer[tempOffset..<(tempOffset + Int(blockSize))])
                tempOffset += Int(blockSize)
                frames.append(frame)
            }

            if !completeBatch {
                break // Wait for more TCP bytes
            }

            rxBuffer.removeSubrange(0..<tempOffset)
            for frame in frames {
                if let ipPacket = handleInboundEthernetFrame(frame) {
                    inboundBatch.append(ipPacket)
                }
            }
        }

        if rxBuffer.isEmpty {
            rxBuffer = Data()
        }

        if !inboundBatch.isEmpty {
            if let batchHandler = onInboundIPPackets {
                batchHandler(inboundBatch)
            } else if let singleHandler = onInboundIPPacket {
                for pkt in inboundBatch {
                    singleHandler(pkt)
                }
            }
        }
    }

    private func handleInboundEthernetFrame(_ frame: Data) -> Data? {
        guard frame.count >= 14 else { return nil }
        let srcMAC = [UInt8](frame[6..<12])
        let etherType = (UInt16(frame[12]) << 8) | UInt16(frame[13])

        if etherType == 0x0806 {
            // ARP Frame
            handleARPFrame(frame, srcMAC: srcMAC)
            return nil
        } else if etherType == 0x0800 {
            // IPv4 Frame
            let ipPacket = Data(frame.dropFirst(14))
            guard ipPacket.count >= 20 else { return nil }

            // Learn Gateway MAC from unicast frames
            if (srcMAC[0] & 0x01) == 0 && srcMAC != myMAC {
                gatewayMAC = srcMAC
            }

            // Check if this is a DHCP Offer/Ack (UDP src port 67, dst port 68)
            if !dhcpCompleted {
                checkAndParseDHCPResponse(ipPacket: ipPacket, serverMAC: srcMAC)
            }

            return ipPacket
        }
        return nil
    }

    // MARK: - Built-in ARP & DHCP Mini-Stack for SoftEther SecureNAT

    private func handleARPFrame(_ frame: Data, srcMAC: [UInt8]) {
        guard frame.count >= 42 else { return }
        let oper = (UInt16(frame[20]) << 8) | UInt16(frame[21])
        let senderIP = [UInt8](frame[28..<32])
        let targetIP = [UInt8](frame[38..<42])

        if senderIP == gatewayIPBytes && (srcMAC[0] & 0x01) == 0 {
            gatewayMAC = srcMAC
        }

        // If ARP Request (oper == 1) asks for our assigned IP, reply with our MAC
        if oper == 1 && targetIP == assignedIPBytes {
            var reply = Data(capacity: 42)
            reply.append(contentsOf: srcMAC)
            reply.append(contentsOf: myMAC)
            reply.append(contentsOf: [0x08, 0x06]) // ARP
            reply.append(contentsOf: [0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x02]) // Reply
            reply.append(contentsOf: myMAC)
            reply.append(contentsOf: assignedIPBytes)
            reply.append(contentsOf: srcMAC)
            reply.append(contentsOf: senderIP)
            sendEthernetFrame(reply)
        }
    }

    private func sendARPRequest(targetIP: [UInt8]) {
        var req = Data(capacity: 42)
        req.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        req.append(contentsOf: myMAC)
        req.append(contentsOf: [0x08, 0x06])
        req.append(contentsOf: [0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x01])
        req.append(contentsOf: myMAC)
        req.append(contentsOf: assignedIPBytes)
        req.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        req.append(contentsOf: targetIP)
        sendEthernetFrame(req)
    }

    private func sendGratuitousARP() {
        sendARPRequest(targetIP: assignedIPBytes)
    }

    private func buildDHCPPacket(options: [UInt8]) -> Data {
        var bootp = Data(count: 240)
        bootp[0] = 0x01 // BOOTREQUEST
        bootp[1] = 0x01 // Ethernet
        bootp[2] = 0x06 // MAC len
        bootp[3] = 0x00
        bootp[4] = UInt8((dhcpXid >> 24) & 0xFF)
        bootp[5] = UInt8((dhcpXid >> 16) & 0xFF)
        bootp[6] = UInt8((dhcpXid >> 8) & 0xFF)
        bootp[7] = UInt8(dhcpXid & 0xFF)
        bootp[10] = 0x80 // Broadcast flag
        for i in 0..<6 { bootp[28 + i] = myMAC[i] }
        // Magic Cookie: 99.130.83.99
        bootp[236] = 99; bootp[237] = 130; bootp[238] = 83; bootp[239] = 99
        bootp.append(contentsOf: options)

        let udpLen = UInt16(8 + bootp.count)
        var udp = Data(capacity: Int(udpLen))
        udp.append(contentsOf: [0x00, 68, 0x00, 67]) // src=68, dst=67
        udp.append(UInt8(udpLen >> 8)); udp.append(UInt8(udpLen & 0xFF))
        udp.append(contentsOf: [0x00, 0x00]) // UDP checksum optional in IPv4
        udp.append(bootp)

        let ipLen = UInt16(20 + udp.count)
        var ip = Data(count: 20)
        ip[0] = 0x45
        ip[2] = UInt8(ipLen >> 8); ip[3] = UInt8(ipLen & 0xFF)
        ip[8] = 64
        ip[9] = 17 // UDP
        ip[16] = 255; ip[17] = 255; ip[18] = 255; ip[19] = 255
        let csum = Self.ipv4HeaderChecksum(ip)
        ip[10] = UInt8(csum >> 8); ip[11] = UInt8(csum & 0xFF)
        ip.append(udp)

        var eth = Data(capacity: 14 + ip.count)
        eth.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        eth.append(contentsOf: myMAC)
        eth.append(contentsOf: [0x08, 0x00])
        eth.append(ip)
        return eth
    }

    private func sendDHCPDiscover() {
        // DHCP Options: MsgType=1 (Discover), ParameterRequestList (Mask, Router, DNS), End
        let eth = buildDHCPPacket(options: [53, 1, 1, 55, 3, 1, 3, 6, 255])
        sendEthernetFrame(eth)
    }

    private func sendDHCPRequest(requestedIP: [UInt8], serverID: [UInt8]) {
        var opts: [UInt8] = [53, 1, 3] // DHCPREQUEST
        opts.append(contentsOf: [50, 4])
        opts.append(contentsOf: requestedIP)
        if serverID.count == 4 {
            opts.append(contentsOf: [54, 4])
            opts.append(contentsOf: serverID)
        }
        opts.append(contentsOf: [55, 3, 1, 3, 6, 255])
        sendEthernetFrame(buildDHCPPacket(options: opts))
    }

    private func checkAndParseDHCPResponse(ipPacket: Data, serverMAC: [UInt8]) {
        let ihl = Int(ipPacket[0] & 0x0F) * 4
        guard ipPacket.count >= ihl + 8 + 240, ipPacket[9] == 17 else { return }
        let srcPort = (UInt16(ipPacket[ihl]) << 8) | UInt16(ipPacket[ihl + 1])
        let dstPort = (UInt16(ipPacket[ihl + 2]) << 8) | UInt16(ipPacket[ihl + 3])
        guard srcPort == 67 && dstPort == 68 else { return }

        let bootp = Data(ipPacket.dropFirst(ihl + 8))
        guard bootp[0] == 0x02 else { return } // BOOTREPLY
        let yiaddr = [UInt8](bootp[16..<20])
        guard yiaddr[0] != 0 else { return }

        var msgType: UInt8 = 0
        var serverID: [UInt8] = [UInt8](bootp[20..<24])
        var idx = 240
        while idx < bootp.count {
            let opt = bootp[idx]
            if opt == 255 { break }
            if opt == 0 { idx += 1; continue }
            guard idx + 1 < bootp.count else { break }
            let len = Int(bootp[idx + 1])
            guard idx + 2 + len <= bootp.count else { break }
            let valStart = idx + 2
            if opt == 53 && len == 1 {
                msgType = bootp[valStart]
            } else if opt == 1 && len == 4 {
                subnetMaskBytes = [UInt8](bootp[valStart..<(valStart + 4)])
            } else if opt == 3 && len >= 4 {
                gatewayIPBytes = [UInt8](bootp[valStart..<(valStart + 4)])
            } else if opt == 6 && len >= 4 {
                var dnsList: [String] = []
                for j in stride(from: 0, to: len - 3, by: 4) {
                    dnsList.append(bootp[(valStart + j)..<(valStart + j + 4)].map(String.init).joined(separator: "."))
                }
                if !dnsList.isEmpty { negotiatedDNSServers = dnsList }
            } else if opt == 54 && len == 4 {
                serverID = [UInt8](bootp[valStart..<(valStart + 4)])
            }
            idx += 2 + len
        }

        assignedIPBytes = yiaddr
        gatewayMAC = serverMAC

        if msgType == 2 { // DHCPOFFER -> commit lease via DHCPREQUEST
            sendDHCPRequest(requestedIP: yiaddr, serverID: serverID)
            if !dhcpCompleted {
                dhcpCompleted = true
                let ipStr = yiaddr.map(String.init).joined(separator: ".")
                log("[DHCP] 从 SecureNAT 分配到内网 IP: \(ipStr)")
                completePendingHandshakeIfNeeded()
            }
        } else {
            if !dhcpCompleted {
                dhcpCompleted = true
                let ipStr = yiaddr.map(String.init).joined(separator: ".")
                log("[DHCP] 从 SecureNAT 确认租约 IP: \(ipStr)")
                completePendingHandshakeIfNeeded()
            }
        }
    }

    private func completePendingHandshakeIfNeeded() {
        guard !isStopped, isRunning, let pending = pendingHandshake else { return }
        pendingHandshake = nil
        let ipStr = assignedIPBytes.map(String.init).joined(separator: ".")
        let maskStr = subnetMaskBytes.map(String.init).joined(separator: ".")
        let gwStr = gatewayIPBytes.map(String.init).joined(separator: ".")
        sendGratuitousARP()
        pending.completion(.success(HandshakeResult(
            sessionName: pending.sessionName,
            assignedIP: ipStr,
            subnetMask: maskStr,
            gatewayIP: gwStr,
            dnsServers: negotiatedDNSServers
        )))
    }

    private static func ipv4HeaderChecksum(_ header: Data) -> UInt16 {
        var sum: UInt32 = 0
        for i in stride(from: 0, to: 20, by: 2) {
            let word = (UInt32(header[i]) << 8) | UInt32(header[i + 1])
            sum += word
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    // MARK: - KeepAlive & HTTP Helpers

    private func sendKeepAlivePacket() {
        guard isRunning, !isStopped else { return }
        var ka = Data(capacity: 16)
        ka.appendBEUInt32(0xFFFFFFFF) // KEEP_ALIVE_MAGIC
        ka.appendBEUInt32(8)
        for _ in 0..<8 { ka.append(UInt8.random(in: 0...255)) }
        addBytesSent(ka.count)
        sendRaw(ka) { [weak self] err in
            guard let self = self, let err = err else { return }
            self.queue.async {
                if self.isRunning && !self.isStopped {
                    self.log("[KeepAlive] 心跳发送失败: \(err.localizedDescription)")
                    self.triggerDisconnect(err)
                }
            }
        }
    }

    private func startKeepAliveTimer() {
        keepAliveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // SoftEther server default TimeOut is 20s; send KeepAlive every 5s with strict leeway
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning, !self.isStopped else { return }
            self.sendKeepAlivePacket()
            self.keepAliveTickCount += 1
            // Periodically refresh SecureNAT ARP entry before its 30s expiration
            if self.keepAliveTickCount % 5 == 0 {
                self.sendGratuitousARP()
            }
        }
        timer.resume()
        self.keepAliveTimer = timer
    }

    private func sendRaw(_ data: Data, completion: @escaping (Error?) -> Void) {
        guard let conn = connection else {
            completion(Self.makeError("连接已关闭"))
            return
        }
        conn.send(content: data, completion: .contentProcessed { err in
            completion(err)
        })
    }

    private func receiveHTTPPack(completion: @escaping (Result<SoftEtherPack, Error>) -> Void) {
        var headerBuf = Data()

        func readUntilHeaderEnd() {
            guard let conn = connection else {
                completion(.failure(Self.makeError("连接未就绪")))
                return
            }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }
                guard let d = data, !d.isEmpty else {
                    completion(.failure(Self.makeError("服务端关闭了连接")))
                    return
                }
                headerBuf.append(d)
                let separator = Data("\r\n\r\n".utf8)
                if let range = headerBuf.range(of: separator) {
                    let headerData = headerBuf[..<range.lowerBound]
                    let bodyPrefix = Data(headerBuf[range.upperBound...])
                    let headerStr = String(decoding: headerData, as: UTF8.self)

                    guard headerStr.contains("200") else {
                        let firstLine = headerStr.components(separatedBy: "\r\n").first ?? headerStr
                        completion(.failure(Self.makeError("HTTP 握手被拒绝: \(firstLine)")))
                        return
                    }

                    var contentLen = 0
                    for line in headerStr.components(separatedBy: "\r\n") {
                        if line.lowercased().hasPrefix("content-length:") {
                            let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                            contentLen = Int(valStr) ?? 0
                        }
                    }

                    guard contentLen > 0 && contentLen <= 1_048_576 else {
                        completion(.failure(Self.makeError("无效的 PACK Content-Length: \(contentLen)")))
                        return
                    }

                    readBodyBytes(existing: bodyPrefix, totalNeeded: contentLen)
                } else {
                    readUntilHeaderEnd()
                }
            }
        }

        func readBodyBytes(existing: Data, totalNeeded: Int) {
            if existing.count >= totalNeeded {
                let packSlice = Data(existing.prefix(totalNeeded))
                if existing.count > totalNeeded {
                    self.rxBuffer.append(existing.dropFirst(totalNeeded))
                }
                if let pack = SoftEtherPack.deserialize(from: packSlice) {
                    completion(.success(pack))
                } else {
                    completion(.failure(Self.makeError("解析 SoftEther PACK 失败")))
                }
                return
            }
            guard let conn = connection else {
                completion(.failure(Self.makeError("连接中断")))
                return
            }
            let remaining = totalNeeded - existing.count
            conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }
                guard let d = data, !d.isEmpty else {
                    completion(.failure(Self.makeError("读取 PACK 负载中断")))
                    return
                }
                var combined = existing
                combined.append(d)
                readBodyBytes(existing: combined, totalNeeded: totalNeeded)
            }
        }

        readUntilHeaderEnd()
    }

    private func log(_ msg: String) {
        onLog?(msg)
    }

    private static func makeError(_ msg: String) -> NSError {
        return NSError(domain: "SoftEtherTunnelSession", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

// MARK: - Data Endian Helpers

extension Data {
    mutating func appendBEUInt32(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendBEUInt64(_ value: UInt64) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func readBEUInt32(at offset: inout Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        let s = startIndex + offset
        let v = (UInt32(self[s]) << 24)
              | (UInt32(self[s + 1]) << 16)
              | (UInt32(self[s + 2]) << 8)
              | UInt32(self[s + 3])
        offset += 4
        return v
    }

    func readBEUInt64(at offset: inout Int) -> UInt64? {
        guard let hi = readBEUInt32(at: &offset),
              let lo = readBEUInt32(at: &offset) else { return nil }
        return (UInt64(hi) << 32) | UInt64(lo)
    }
}
