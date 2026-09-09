// swiftlint:disable file_length
import Foundation
import Network
import CryptoKit

struct IAXConfig {
    var myNode: String       // our AllStarLink node number
    var password: String     // that node's password (registration secret)
    var targetNode: String   // node to link to
    var host: String         // resolved target address
    var port: UInt16         // resolved target port, usually 4569
    var callsign: String
    var registrar = "register.allstarlink.org"
    var registrarPort: UInt16 = 4569
}

// The RFC 5456 subset AllStar needs: MD5 registration with the ASL
// registrar (so other nodes can verify our node number), then one
// outbound call to the target node carrying µ-law voice both ways.
// Keying is "oldkey" style — audio present means keyed — which every
// app_rpt version accepts from a link partner.
private enum IAX {
    // Frame types
    static let typeDTMF: UInt8 = 1
    static let typeVoice: UInt8 = 2
    static let typeControl: UInt8 = 4
    static let typeIAX: UInt8 = 6
    static let typeText: UInt8 = 7

    // IAX subclasses
    static let new: UInt32 = 1, ping: UInt32 = 2, pong: UInt32 = 3, ack: UInt32 = 4
    static let hangup: UInt32 = 5, reject: UInt32 = 6, accept: UInt32 = 7
    static let authreq: UInt32 = 8, authrep: UInt32 = 9, inval: UInt32 = 10
    static let lagrq: UInt32 = 11, lagrp: UInt32 = 12
    static let regreq: UInt32 = 13, regauth: UInt32 = 14, regack: UInt32 = 15, regrej: UInt32 = 16
    static let vnak: UInt32 = 18
    static let callToken: UInt32 = 40

    // Control subclasses
    static let ctrlHangup: UInt32 = 1, ctrlRinging: UInt32 = 3, ctrlAnswer: UInt32 = 4
    static let ctrlBusy: UInt32 = 5, ctrlCongestion: UInt32 = 8
    static let ctrlKey: UInt32 = 12, ctrlUnkey: UInt32 = 13
    static let ctrlProgress: UInt32 = 14, ctrlProceeding: UInt32 = 15

    // Information elements
    static let ieCalledNumber: UInt8 = 1, ieCallingNumber: UInt8 = 2, ieCallingName: UInt8 = 4
    static let ieUsername: UInt8 = 6, ieCapability: UInt8 = 8, ieFormat: UInt8 = 9
    static let ieVersion: UInt8 = 11, ieAuthMethods: UInt8 = 14, ieChallenge: UInt8 = 15
    static let ieMD5Result: UInt8 = 16, ieRefresh: UInt8 = 19, ieCause: UInt8 = 22
    static let ieCallToken: UInt8 = 54

    static let formatUlaw: UInt32 = 4      // AST_FORMAT_ULAW
    static let authMD5: UInt16 = 2
}

private struct IAXFullFrame {
    var srcCall: UInt16
    var dstCall: UInt16
    var timestamp: UInt32
    var oseq: UInt8
    var iseq: UInt8
    var type: UInt8
    var sub: UInt32
    var data: Data

    // Frames that never advance sequence numbers on either side
    var countsForSeq: Bool {
        !(type == IAX.typeIAX && [IAX.ack, IAX.inval, IAX.vnak, IAX.callToken].contains(sub))
    }

    static func parse(_ raw: Data) -> IAXFullFrame? {
        guard raw.count >= 12 else { return nil }
        let bytes = [UInt8](raw)
        let word0 = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard word0 & 0x8000 != 0 else { return nil }
        let rawSub = bytes[11]
        let sub: UInt32 = rawSub & 0x80 != 0 ? 1 << UInt32(rawSub & 0x7F) : UInt32(rawSub)
        return IAXFullFrame(
            srcCall: word0 & 0x7FFF,
            dstCall: (UInt16(bytes[2]) << 8 | UInt16(bytes[3])) & 0x7FFF,
            timestamp: UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16
                | UInt32(bytes[6]) << 8 | UInt32(bytes[7]),
            oseq: bytes[8], iseq: bytes[9], type: bytes[10], sub: sub,
            data: raw.count > 12 ? raw.subdata(in: raw.startIndex + 12..<raw.endIndex) : Data()
        )
    }
}

// TLV information-element blob from a full frame
private struct IAXIEs {
    private var fields: [UInt8: Data] = [:]

    init(_ data: Data) {
        var cursor = data.startIndex
        while cursor + 1 < data.endIndex {
            let key = data[cursor]
            let len = Int(data[cursor + 1])
            let start = cursor + 2
            guard start + len <= data.endIndex else { break }
            fields[key] = data.subdata(in: start..<start + len)
            cursor = start + len
        }
    }

    subscript(_ key: UInt8) -> Data? { fields[key] }

    func str(_ key: UInt8) -> String? {
        fields[key].flatMap { String(data: $0, encoding: .utf8) }
    }

    func u16(_ key: UInt8) -> UInt16? {
        guard let raw = fields[key], raw.count == 2 else { return nil }
        return UInt16(raw[raw.startIndex]) << 8 | UInt16(raw[raw.startIndex + 1])
    }
}

// One IAX2 dialog: a UDP socket to one peer, our call number, and the
// sequence/timestamp state the wire format needs.
private final class IAXDialog {
    let conn: NWConnection
    let localCall: UInt16
    var remoteCall: UInt16 = 0
    var oseq: UInt8 = 0
    var iseq: UInt8 = 0
    let epoch = Date()
    var lastHeard = Date()

    var onFull: ((IAXFullFrame) -> Void)?
    var onMini: ((Data) -> Void)?
    var onFailed: ((String) -> Void)?
    var onReady: (() -> Void)?

    init(host: String, port: UInt16, localCall: UInt16, queue: DispatchQueue) {
        self.localCall = localCall
        conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 4569,
            using: .udp
        )
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onReady?()
                self?.receiveLoop()
            case .failed(let err):
                self?.onFailed?(err.localizedDescription)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func cancel() {
        conn.cancel()
    }

    var nowMs: UInt32 {
        UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince(epoch) * 1000))
    }

    private func receiveLoop() {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lastHeard = Date()
                self.dispatch(data)
            }
            if error == nil { self.receiveLoop() }
        }
    }

    private func dispatch(_ data: Data) {
        let word0 = UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1])
        if word0 & 0x8000 != 0 {
            guard let frame = IAXFullFrame.parse(data) else { return }
            onFull?(frame)
        } else if word0 != 0, data.count > 4 {
            // Mini voice frame: 16-bit call number, 16-bit timestamp, payload
            onMini?(data.subdata(in: data.startIndex + 4..<data.endIndex))
        }
        // word0 == 0 is a meta/trunk frame; we never negotiate trunking
    }

    func sendFull(type: UInt8, sub: UInt32, ies: [(UInt8, Data)] = [],
                  timestamp: UInt32? = nil, payload: Data = Data()) {
        let stamp = timestamp ?? nowMs
        let counts = !(type == IAX.typeIAX
            && [IAX.ack, IAX.inval, IAX.vnak, IAX.callToken].contains(sub))
        var pkt = [UInt8]()
        pkt.reserveCapacity(12 + 32)
        pkt.append(UInt8(0x80 | (localCall >> 8)))
        pkt.append(UInt8(localCall & 0xFF))
        pkt.append(UInt8(remoteCall >> 8))
        pkt.append(UInt8(remoteCall & 0xFF))
        pkt.append(contentsOf: withUnsafeBytes(of: stamp.bigEndian, Array.init))
        pkt.append(oseq)
        pkt.append(iseq)
        pkt.append(type)
        pkt.append(UInt8(sub & 0x7F))   // every subclass we send fits 7 bits
        for (key, value) in ies {
            pkt.append(key)
            pkt.append(UInt8(value.count))
            pkt.append(contentsOf: value)
        }
        pkt.append(contentsOf: payload)
        if counts { oseq &+= 1 }
        conn.send(content: Data(pkt), completion: .contentProcessed { _ in })
    }

    func sendMini(timestamp: UInt16, payload: Data) {
        var pkt = [UInt8]()
        pkt.reserveCapacity(4 + payload.count)
        pkt.append(UInt8(localCall >> 8))
        pkt.append(UInt8(localCall & 0xFF))
        pkt.append(UInt8(timestamp >> 8))
        pkt.append(UInt8(timestamp & 0xFF))
        pkt.append(contentsOf: payload)
        conn.send(content: Data(pkt), completion: .contentProcessed { _ in })
    }

    func ack(_ frame: IAXFullFrame) {
        sendFull(type: IAX.typeIAX, sub: IAX.ack, timestamp: frame.timestamp)
    }

    // Advance iseq for a counting frame; duplicates get re-ACKed by the
    // caller but must not advance state twice.
    func noteReceived(_ frame: IAXFullFrame) -> Bool {
        guard frame.countsForSeq else { return true }
        if frame.oseq == iseq {
            iseq &+= 1
            return true
        }
        // Retransmit of something we already processed
        let behind = iseq &- frame.oseq
        return behind == 0 || behind > 128
    }
}

// MARK: - Client

// swiftlint:disable:next type_body_length
final class IAXClient {
    private let config: IAXConfig
    private let queue = DispatchQueue(label: "allstar.iax")
    private var reg: IAXDialog?
    private var call: IAXDialog?
    private var timer: DispatchSourceTimer?
    private var regTimer: DispatchSourceTimer?
    private var nextCallNumber: UInt16 = 1

    private(set) var state: LinkState = .idle {
        didSet { onState?(state) }
    }

    var onState: ((LinkState) -> Void)?
    var onLog: ((String, Bool) -> Void)?
    var onRemoteKey: ((Bool) -> Void)?
    var onAudio: (([Float]) -> Void)?

    // RX keying: oldkey has no explicit signal, so voice activity opens a
    // transmission and ~600 ms of silence closes it. Newkey partners also
    // send KEY/UNKEY control frames, which we honor when present.
    private var remoteKeyed = false
    private var lastVoice = Date.distantPast

    // TX
    private var transmitting = false
    private var sentTxFull = false
    private var lastTxTimestamp: UInt32 = 0

    private var registered = false
    private var stateSince = Date()

    init(config: IAXConfig) {
        self.config = config
    }

    func connect() {
        queue.async { [self] in
            setState(.connecting)
            log("registering node \(config.myNode) with \(config.registrar)")
            startRegistration()
            startTimer()
        }
    }

    func disconnect() {
        queue.async { [self] in
            if let call, call.remoteCall != 0 {
                call.sendFull(type: IAX.typeIAX, sub: IAX.hangup)
            }
            teardown()
            setState(.idle)
        }
    }

    // MARK: - Registration

    private func startRegistration() {
        reg?.cancel()
        let dialog = IAXDialog(
            host: config.registrar, port: config.registrarPort,
            localCall: allocCallNumber(), queue: queue
        )
        dialog.onFailed = { [weak self] why in self?.fail("registrar: \(why)") }
        dialog.onReady = { [weak self] in self?.sendRegReq(auth: nil) }
        dialog.onFull = { [weak self] frame in self?.handleRegFrame(frame) }
        reg = dialog
    }

    private func sendRegReq(auth challenge: String?) {
        guard let reg else { return }
        var ies: [(UInt8, Data)] = [
            (IAX.ieUsername, Data(config.myNode.utf8)),
            (IAX.ieRefresh, Data([0, 60]))
        ]
        if let challenge {
            ies.append((IAX.ieMD5Result, Data(md5Response(challenge).utf8)))
        } else {
            ies.append((IAX.ieCallToken, Data()))
        }
        reg.sendFull(type: IAX.typeIAX, sub: IAX.regreq, ies: ies)
    }

    private func handleRegFrame(_ frame: IAXFullFrame) {
        guard let reg else { return }
        reg.remoteCall = frame.srcCall
        guard reg.noteReceived(frame), frame.type == IAX.typeIAX else { return }
        let ies = IAXIEs(frame.data)
        switch frame.sub {
        case IAX.callToken:
            // Registrar wants the token echoed; redo the REGREQ with it
            reg.oseq = 0
            reg.iseq = 0
            reg.remoteCall = 0
            var tokenIEs: [(UInt8, Data)] = [
                (IAX.ieUsername, Data(config.myNode.utf8)),
                (IAX.ieRefresh, Data([0, 60]))
            ]
            tokenIEs.append((IAX.ieCallToken, ies[IAX.ieCallToken] ?? Data()))
            reg.sendFull(type: IAX.typeIAX, sub: IAX.regreq, ies: tokenIEs)
        case IAX.regauth:
            guard let challenge = ies.str(IAX.ieChallenge) else {
                fail("registrar sent no challenge")
                return
            }
            sendRegReq(auth: challenge)
        case IAX.regack:
            reg.ack(frame)
            let refresh = ies.u16(IAX.ieRefresh) ?? 60
            if !registered {
                registered = true
                log("registered (refresh \(refresh)s)")
                startCall()
            }
            scheduleReRegistration(after: max(30, Int(refresh)) - 15)
        case IAX.regrej:
            reg.ack(frame)
            fail("registration rejected — check node number and password")
        default:
            break
        }
    }

    private func scheduleReRegistration(after seconds: Int) {
        regTimer?.cancel()
        let timerSource = DispatchSource.makeTimerSource(queue: queue)
        timerSource.schedule(deadline: .now() + .seconds(seconds))
        timerSource.setEventHandler { [weak self] in self?.startRegistration() }
        timerSource.resume()
        regTimer = timerSource
    }

    // MARK: - Call

    private func startCall() {
        setState(.login)
        log("calling node \(config.targetNode) at \(config.host):\(config.port)")
        let dialog = IAXDialog(
            host: config.host, port: config.port,
            localCall: allocCallNumber(), queue: queue
        )
        dialog.onFailed = { [weak self] why in self?.fail(why) }
        dialog.onReady = { [weak self] in self?.sendNew(token: nil) }
        dialog.onFull = { [weak self] frame in self?.handleCallFrame(frame) }
        dialog.onMini = { [weak self] payload in self?.handleVoice(payload) }
        call = dialog
    }

    // app_rpt convention: dial the remote node number, identify ourselves
    // via the calling number, username "radio" like every nodes-list entry
    private func newIEs(token: Data?) -> [(UInt8, Data)] {
        [
            (IAX.ieVersion, Data([0, 2])),
            (IAX.ieCalledNumber, Data(config.targetNode.utf8)),
            (IAX.ieCallingNumber, Data(config.myNode.utf8)),
            (IAX.ieCallingName, Data(config.callsign.uppercased().utf8)),
            (IAX.ieUsername, Data("radio".utf8)),
            (IAX.ieFormat, Data([0, 0, 0, UInt8(IAX.formatUlaw)])),
            (IAX.ieCapability, Data([0, 0, 0, UInt8(IAX.formatUlaw)])),
            (IAX.ieCallToken, token ?? Data())
        ]
    }

    private func sendNew(token: Data?) {
        call?.sendFull(type: IAX.typeIAX, sub: IAX.new, ies: newIEs(token: token))
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleCallFrame(_ frame: IAXFullFrame) {
        guard let call else { return }
        if call.remoteCall == 0, frame.srcCall != 0 {
            call.remoteCall = frame.srcCall
        }
        guard call.noteReceived(frame) else {
            call.ack(frame)
            return
        }
        let ies = IAXIEs(frame.data)
        switch frame.type {
        case IAX.typeIAX:
            handleCallIAX(frame, ies: ies, on: call)
        case IAX.typeControl:
            handleControl(frame, on: call)
        case IAX.typeVoice:
            call.ack(frame)
            if frame.sub == IAX.formatUlaw {
                handleVoice(frame.data)
            } else if remoteKeyed == false {
                log("unexpected voice format \(frame.sub)", error: true)
            }
        case IAX.typeText:
            call.ack(frame)
            if let text = String(data: frame.data, encoding: .utf8),
               !text.hasPrefix("!") {   // !NEWKEY! and friends are signalling
                log("text: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        case IAX.typeDTMF:
            call.ack(frame)
        default:
            call.ack(frame)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleCallIAX(_ frame: IAXFullFrame, ies: IAXIEs, on call: IAXDialog) {
        switch frame.sub {
        case IAX.callToken:
            call.oseq = 0
            call.iseq = 0
            call.remoteCall = 0
            sendNew(token: ies[IAX.ieCallToken] ?? Data())
        case IAX.authreq:
            setState(.authorising)
            guard let challenge = ies.str(IAX.ieChallenge) else {
                fail("node sent no challenge")
                return
            }
            call.sendFull(type: IAX.typeIAX, sub: IAX.authrep,
                          ies: [(IAX.ieMD5Result, Data(md5Response(challenge).utf8))])
        case IAX.accept:
            call.ack(frame)
            setState(.configuring)
        case IAX.reject:
            call.ack(frame)
            fail("node refused: \(ies.str(IAX.ieCause) ?? "rejected")")
        case IAX.hangup:
            call.ack(frame)
            fail("node hung up" + (ies.str(IAX.ieCause).map { ": \($0)" } ?? ""))
        case IAX.ping:
            call.sendFull(type: IAX.typeIAX, sub: IAX.pong, timestamp: frame.timestamp)
        case IAX.lagrq:
            call.sendFull(type: IAX.typeIAX, sub: IAX.lagrp, timestamp: frame.timestamp)
        case IAX.pong, IAX.lagrp:
            call.ack(frame)
        case IAX.inval:
            fail("node invalidated the call")
        case IAX.vnak:
            break   // coarse recovery: the watchdog will fail us if stuck
        default:
            call.ack(frame)
        }
    }

    private func handleControl(_ frame: IAXFullFrame, on call: IAXDialog) {
        call.ack(frame)
        switch frame.sub {
        case IAX.ctrlAnswer:
            if state != .running {
                setState(.running)
                log("linked to node \(config.targetNode)")
            }
        case IAX.ctrlKey:
            setRemoteKeyed(true)
        case IAX.ctrlUnkey:
            setRemoteKeyed(false)
        case IAX.ctrlHangup:
            fail("node hung up")
        case IAX.ctrlBusy, IAX.ctrlCongestion:
            fail("node busy")
        case IAX.ctrlRinging, IAX.ctrlProgress, IAX.ctrlProceeding:
            break
        default:
            break
        }
    }

    private func handleVoice(_ payload: Data) {
        guard !payload.isEmpty else { return }
        lastVoice = Date()
        if !remoteKeyed { setRemoteKeyed(true) }
        // Some nodes answer only once audio flows
        if state == .configuring { setState(.running) }
        onAudio?(Ulaw.decode(payload))
    }

    private func setRemoteKeyed(_ keyed: Bool) {
        guard keyed != remoteKeyed else { return }
        remoteKeyed = keyed
        onRemoteKey?(keyed)
    }

    // MARK: - Transmit

    func startTransmit() {
        queue.async { [self] in
            guard state == .running else { return }
            transmitting = true
            sentTxFull = false
        }
    }

    // 160 samples of 8 kHz S16 from the mic, every 20 ms
    func sendVoice(_ pcm: [Int16]) {
        queue.async { [self] in
            guard transmitting, let call, state == .running else { return }
            let payload = Ulaw.encode(pcm)
            let stamp = call.nowMs
            // A full voice frame opens each transmission (it pins the codec
            // and the timestamp base) and re-pins on 16-bit wrap
            if !sentTxFull || (stamp & 0xFFFF) < (lastTxTimestamp & 0xFFFF) {
                sentTxFull = true
                call.sendFull(type: IAX.typeVoice, sub: IAX.formatUlaw,
                              timestamp: stamp, payload: payload)
            } else {
                call.sendMini(timestamp: UInt16(stamp & 0xFFFF), payload: payload)
            }
            lastTxTimestamp = stamp
        }
    }

    func endTransmit() {
        queue.async { [self] in
            transmitting = false
        }
    }

    // MARK: - Plumbing

    private func allocCallNumber() -> UInt16 {
        defer { nextCallNumber = nextCallNumber % 0x7FFE + 1 }
        return nextCallNumber
    }

    private func md5Response(_ challenge: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((challenge + config.password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func startTimer() {
        let timerSource = DispatchSource.makeTimerSource(queue: queue)
        timerSource.schedule(deadline: .now() + 1, repeating: 1)
        timerSource.setEventHandler { [weak self] in self?.tick() }
        timerSource.resume()
        timer = timerSource
    }

    private var lastPing = Date.distantPast

    private func tick() {
        // Voice-activity unkey
        if remoteKeyed, Date().timeIntervalSince(lastVoice) > 0.6 {
            setRemoteKeyed(false)
        }
        let stuck = Date().timeIntervalSince(stateSince)
        switch state {
        case .connecting where stuck > 10:
            fail("registration timed out")
        case .login where stuck > 8, .authorising where stuck > 8:
            fail("no answer from node")
        case .configuring where stuck > 10:
            fail("node accepted but never answered")
        case .running:
            if let call {
                if Date().timeIntervalSince(call.lastHeard) > 60 {
                    fail("link lost")
                } else if Date().timeIntervalSince(lastPing) > 15 {
                    lastPing = Date()
                    call.sendFull(type: IAX.typeIAX, sub: IAX.ping)
                }
            }
        default:
            break
        }
    }

    private func setState(_ new: LinkState) {
        guard new != state else { return }
        stateSince = Date()
        state = new
    }

    private func teardown() {
        timer?.cancel()
        timer = nil
        regTimer?.cancel()
        regTimer = nil
        reg?.cancel()
        reg = nil
        call?.cancel()
        call = nil
        registered = false
        transmitting = false
        if remoteKeyed { setRemoteKeyed(false) }
    }

    private func fail(_ why: String) {
        guard state != .idle else { return }
        log(why, error: true)
        teardown()
        setState(.failed(why))
    }

    private func log(_ line: String, error: Bool = false) {
        onLog?(line, error)
    }
}
