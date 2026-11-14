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
    private var rxBuffer = Data()
    private var isRunning = false
    private var keepAliveTimer: DispatchSourceTimer?

    // Virtual L2 Adapter MAC & Learned Gateway MAC
    private let myMAC: [UInt8]
    private var gatewayMAC: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
    private var assignedIPBytes: [UInt8] = [192, 168, 30, 18]
    private var gatewayIPBytes: [UInt8] = [192, 168, 30, 1]
    private var subnetMaskBytes: [UInt8] = [255, 255, 255, 0]
    private var dhcpCompleted = false
    private let dhcpXid: UInt32 = UInt32.random(in: 1...0x7FFFFFFF)

    public var onInboundIPPacket: ((Data) -> Void)?
    public var onLog: ((String) -> Void)?
    public private(set) var totalBytesSent: UInt64 = 0
    public private(set) var totalBytesRecv: UInt64 = 0

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
        let tlsOptions = NWProtocolTLS.Options()
        let secOpts = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_tls_min_version(secOpts, .TLSv12)
        sec_protocol_options_set_verify_block(secOpts, { _, _, complete in
            complete(true) // SoftEther servers use self-signed certificates by default
        }, queue)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 20

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(Self.makeError("无效端口: \(port)")))
            return
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        self.connection = conn

        var handshakeEntered = false
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                guard !handshakeEntered else { return }
                handshakeEntered = true
                self.log("[TLS] 已建立到 \(self.host):\(self.port) 的加密通道")
                self.performWatermarkAndAuth(completion: completion)
            case .failed(let err):
                if !handshakeEntered {
                    handshakeEntered = true
                    completion(.failure(err))
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    public func stop() {
        isRunning = false
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        connection?.cancel()
        connection = nil
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
                    self.log("[Welcome] 认证成功！会话已建立: \(sessionName)")

                    self.isRunning = true
                    self.startKeepAliveTimer()
                    self.startDataStreamLoop()

                    // Trigger DHCP Discover + ARP probe for SecureNAT gateway (192.168.30.1)
                    self.sendDHCPDiscover()
                    self.sendARPRequest(targetIP: self.gatewayIPBytes)

                    // Wait up to 2.5s for SecureNAT DHCP Offer, or use 192.168.30.18 fallback
                    self.queue.asyncAfter(deadline: .now() + 2.5) {
                        let ipStr = self.assignedIPBytes.map(String.init).joined(separator: ".")
                        let maskStr = self.subnetMaskBytes.map(String.init).joined(separator: ".")
                        let gwStr = self.gatewayIPBytes.map(String.init).joined(separator: ".")
                        self.sendGratuitousARP()
                        completion(.success(HandshakeResult(
                            sessionName: sessionName,
                            assignedIP: ipStr,
                            subnetMask: maskStr,
                            gatewayIP: gwStr,
                            dnsServers: ["8.8.8.8", "1.1.1.1"]
                        )))
                    }
                }
            }
        }
    }

    // MARK: - L3 IPv4 -> L2 Ethernet Encapsulation

    public func sendIPv4Packet(_ ipPacket: Data) {
        guard isRunning, ipPacket.count >= 20 else { return }
        // Check IPv4 version nibble
        let version = (ipPacket[ipPacket.startIndex] >> 4) & 0x0F
        guard version == 4 else { return }

        var ethFrame = Data(capacity: 14 + ipPacket.count)
        ethFrame.append(contentsOf: gatewayMAC) // Destination MAC (SecureNAT Gateway)
        ethFrame.append(contentsOf: myMAC)      // Source MAC
        ethFrame.append(contentsOf: [0x08, 0x00]) // EtherType: IPv4
        ethFrame.append(ipPacket)

        sendEthernetFrame(ethFrame)
    }

    private func sendEthernetFrame(_ frame: Data) {
        var blockStream = Data(capacity: 8 + frame.count)
        blockStream.appendBEUInt32(1) // 1 block
        blockStream.appendBEUInt32(UInt32(frame.count))
        blockStream.append(frame)
        totalBytesSent += UInt64(blockStream.count)
        sendRaw(blockStream) { _ in }
    }

    // MARK: - Inbound SoftEther Stream & L2 -> L3 Decapsulation

    private func startDataStreamLoop() {
        guard isRunning, let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, self.isRunning else { return }
            if let d = data, !d.isEmpty {
                self.totalBytesRecv += UInt64(d.count)
                self.rxBuffer.append(d)
                self.processRxStreamBuffer()
            }
            if isComplete || error != nil {
                self.isRunning = false
                return
            }
            self.startDataStreamLoop()
        }
    }

    private func processRxStreamBuffer() {
        while rxBuffer.count >= 8 {
            var offset = 0
            guard let numBlocks = rxBuffer.readBEUInt32(at: &offset) else { return }

            if numBlocks == 0xFFFFFFFF {
                // KEEP_ALIVE_MAGIC
                guard let kaSize = rxBuffer.readBEUInt32(at: &offset),
                      kaSize <= 65536 else { return }
                guard rxBuffer.count >= 8 + Int(kaSize) else { return }
                rxBuffer.removeSubrange(0..<(8 + Int(kaSize)))
                continue
            }

            if numBlocks == 0 || numBlocks > 512 {
                rxBuffer.removeAll()
                return
            }

            var tempOffset = offset
            var frames: [Data] = []
            var completeBatch = true

            for _ in 0..<numBlocks {
                guard let blockSize = rxBuffer.readBEUInt32(at: &tempOffset),
                      blockSize <= 65536 else {
                    completeBatch = false
                    break
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
                return // Wait for more TCP bytes
            }

            rxBuffer.removeSubrange(0..<tempOffset)
            for frame in frames {
                handleInboundEthernetFrame(frame)
            }
        }
    }

    private func handleInboundEthernetFrame(_ frame: Data) {
        guard frame.count >= 14 else { return }
        let srcMAC = [UInt8](frame[6..<12])
        let etherType = (UInt16(frame[12]) << 8) | UInt16(frame[13])

        if etherType == 0x0806 {
            // ARP Frame
            handleARPFrame(frame, srcMAC: srcMAC)
        } else if etherType == 0x0800 {
            // IPv4 Frame
            let ipPacket = Data(frame.dropFirst(14))
            guard ipPacket.count >= 20 else { return }

            // Learn Gateway MAC from unicast frames
            if (srcMAC[0] & 0x01) == 0 && srcMAC != myMAC {
                gatewayMAC = srcMAC
            }

            // Check if this is a DHCP Offer/Ack (UDP src port 67, dst port 68)
            if !dhcpCompleted {
                checkAndParseDHCPResponse(ipPacket: ipPacket, serverMAC: srcMAC)
            }

            onInboundIPPacket?(ipPacket)
        }
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

    private func sendDHCPDiscover() {
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
        // DHCP Options: MsgType=1 (Discover), ParameterRequestList (Mask, Router, DNS), End
        bootp.append(contentsOf: [53, 1, 1, 55, 3, 1, 3, 6, 255])

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
        sendEthernetFrame(eth)
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
        if yiaddr[0] != 0 {
            assignedIPBytes = yiaddr
            gatewayMAC = serverMAC
            dhcpCompleted = true
            let ipStr = yiaddr.map(String.init).joined(separator: ".")
            log("[DHCP] 从 SecureNAT 分配到内网 IP: \(ipStr)")
        }
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

    private func startKeepAliveTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            var ka = Data()
            ka.appendBEUInt32(0xFFFFFFFF) // KEEP_ALIVE_MAGIC
            ka.appendBEUInt32(8)
            for _ in 0..<8 { ka.append(UInt8.random(in: 0...255)) }
            self.sendRaw(ka) { _ in }
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
