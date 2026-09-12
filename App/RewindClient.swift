import CryptoKit
import Foundation
import Network

// MARK: - RewindConfig

struct RewindConfig {
    var host: String
    var port: UInt16
    var dmrID: UInt32
    var password: String
    var talkgroups: [UInt32]
}

// MARK: - RewindClient

// Speaks BrandMeister's Open DMR Terminal Protocol (Rewind framing).
// Receive-only: logs in, subscribes to talkgroups, hands AMBE frames up.
// swiftlint:disable:next type_body_length
final class RewindClient {
    // MARK: Lifecycle

    init(config: RewindConfig) {
        self.config = config
    }

    // MARK: Internal

    var onState: ((LinkState) -> Void)?
    var onLog: ((String, Bool) -> Void)?
    var onCallStart: ((_ callID: UInt32, _ src: UInt32, _ dst: UInt32) -> Void)?
    var onAudio: ((_ frames: [[CChar]], _ dst: UInt32) -> Void)?
    var onCallEnd: ((_ callID: UInt32) -> Void)?

    private(set) var state: LinkState = .idle {
        didSet { onState?(state) }
    }

    func connect() {
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            state = .failed("bad port")
            return
        }
        state = .connecting
        log("connecting to \(config.host):\(config.port) (open terminal)")
        let connection = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .udp)
        conn = connection
        connection.stateUpdateHandler = { [weak self] st in
            guard let self else {
                return
            }
            switch st {
            case .ready:
                log("udp socket ready")
                state = .login
                lastAck = Date()
                sendKeepAlive()
                startTimer()
                receiveLoop()
            case let .failed(err):
                fail(err.localizedDescription)
            case .cancelled:
                state = .idle
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            timer?.cancel()
            timer = nil
            if state == .running {
                log("→ close session")
                sendFrame(.close, [])
            }
            conn?.cancel()
            conn = nil
            state = .idle
        }
    }

    func startTransmit(dst: UInt32) {
        queue.async { [weak self] in
            guard let self, state == .running else {
                return
            }
            log("TX start → TG \(dst)")
            sendRT(.headerWithFLC, flcPayload(dst: dst, src: config.dmrID))
        }
    }

    /// 27 bytes: three 9-byte on-air AMBE frames (60 ms of audio)
    func sendTransmitAudio(_ bytes: [UInt8]) {
        queue.async { [weak self] in
            guard let self, state == .running, bytes.count == 27 else {
                return
            }
            sendRT(.dmrAudioFrame, bytes)
        }
    }

    func endTransmit(dst: UInt32) {
        queue.async { [weak self] in
            guard let self, state == .running else {
                return
            }
            let flc = flcPayload(dst: dst, src: config.dmrID)
            sendRT(.terminatorWithFLC, flc)
            sendRT(.terminatorWithFLC, flc)
            log("TX end")
        }
    }

    /// Runtime subscription change while connected
    func setSubscription(_ tg: UInt32, active: Bool) {
        queue.async { [weak self] in
            guard let self, state == .running else {
                return
            }
            var payload = [UInt8](le32(7))
            payload.append(contentsOf: le32(tg))
            if active {
                log("→ subscribe TG \(tg)")
                sendFrame(.subscription, payload)
            } else {
                log("→ unsubscribe TG \(tg)")
                sendFrame(.cancelling, payload)
            }
        }
    }

    // MARK: Private

    private enum MsgType: UInt16 {
        case keepAlive = 0x0000
        case close = 0x0001
        case challenge = 0x0002
        case authentication = 0x0003
        case report = 0x0100
        case busyNotice = 0x0200
        case addressNotice = 0x0201
        case bindingNotice = 0x0202
        case subscription = 0x0901
        case cancelling = 0x0902
        case headerWithFLC = 0x0911
        case terminatorWithFLC = 0x0912
        case dmrAudioFrame = 0x0920
        case dmrEmbeddedData = 0x0927
        case failureCode = 0x0929
    }

    private static let sign = Array("REWIND01".utf8)

    private static let serviceOpenTerminal: UInt8 = 0x21
    private static let description = "DMRMonitor iOS 0.2"

    private let config: RewindConfig
    private let queue = DispatchQueue(label: "rewind.net")
    private var conn: NWConnection?
    private var timer: DispatchSourceTimer?
    private var seq: UInt32 = 0
    private var rtSeq: UInt32 = 0
    private var lastAck = Date()

    // Call tracking: OTP has no stream IDs, new calls are detected by a gap
    // in the header frames' realtime sequence counter.
    private var lastHeaderSeq: UInt32?
    private var currentCallID: UInt32 = 0
    private var currentDst: UInt32 = 0

    // MARK: - Outbound

    private func sendFrame(_ type: MsgType, _ payload: [UInt8]) {
        var packet = Data(Self.sign)
        packet.append(le16(type.rawValue))
        packet.append(le16(0)) // flags
        packet.append(le32(seq))
        seq &+= 1
        packet.append(le16(UInt16(payload.count)))
        packet.append(contentsOf: payload)
        conn?.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func sendKeepAlive() {
        var payload = [UInt8](le32(config.dmrID))
        payload.append(Self.serviceOpenTerminal)
        payload.append(contentsOf: Array(Self.description.utf8))
        sendFrame(.keepAlive, payload)
    }

    private func sendAuth(token: [UInt8]) {
        state = .authorising
        var input = Data(token)
        input.append(contentsOf: config.password.utf8)
        let digest = SHA256.hash(data: input)
        log("→ auth response")
        sendFrame(.authentication, Array(digest))
    }

    private func sendSubscriptions() {
        for tg in config.talkgroups {
            log("→ subscribe TG \(tg)")
            var payload = [UInt8](le32(7)) // 7 = group call
            payload.append(contentsOf: le32(tg))
            sendFrame(.subscription, payload)
        }
    }

    // MARK: - Transmit

    /// FLC body as pyspot builds it: flags, feature set, service options,
    /// then 3-byte BE dst and src
    private func flcPayload(dst: UInt32, src: UInt32) -> [UInt8] {
        var payload: [UInt8] = [0x00, 0x00, 0x04]
        payload.append(contentsOf: [UInt8((dst >> 16) & 0xFF), UInt8((dst >> 8) & 0xFF), UInt8(dst & 0xFF)])
        payload.append(contentsOf: [UInt8((src >> 16) & 0xFF), UInt8((src >> 8) & 0xFF), UInt8(src & 0xFF)])
        payload.append(contentsOf: [0x00, 0x00, 0x00])
        return payload
    }

    private func sendRT(_ type: MsgType, _ payload: [UInt8]) {
        var packet = Data(Self.sign)
        packet.append(le16(type.rawValue))
        packet.append(le16(1)) // REWIND_FLAG_REAL_TIME_1
        packet.append(le32(rtSeq))
        rtSeq &+= 1
        packet.append(le16(UInt16(payload.count)))
        packet.append(contentsOf: payload)
        conn?.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func startTimer() {
        let dispatchTimer = DispatchSource.makeTimerSource(queue: queue)
        dispatchTimer.schedule(deadline: .now() + 5, repeating: 5)
        dispatchTimer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            if Date().timeIntervalSince(lastAck) > 15 {
                fail("no reply from master")
                return
            }
            sendKeepAlive()
        }
        dispatchTimer.resume()
        timer = dispatchTimer
    }

    // MARK: - Inbound

    private func receiveLoop() {
        conn?.receiveMessage { [weak self] data, _, _, error in
            guard let self else {
                return
            }
            if let data {
                handle(data)
            }
            if error == nil {
                receiveLoop()
            }
        }
    }

    private func handle(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= Self.sign.count + 10,
              Array(b[0 ..< Self.sign.count]) == Self.sign
        else {
            return
        }

        let base = Self.sign.count
        let rawType = UInt16(b[base]) | UInt16(b[base + 1]) << 8
        let msgSeq = UInt32(b[base + 4]) | UInt32(b[base + 5]) << 8
            | UInt32(b[base + 6]) << 16 | UInt32(b[base + 7]) << 24
        let payload = Array(b[(base + 10)...])

        guard let type = MsgType(rawValue: rawType) else {
            log("← unhandled type 0x\(String(rawType, radix: 16))")
            return
        }

        switch type {
        case .challenge:
            handleChallenge(payload)

        case .keepAlive:
            handleKeepAliveMessage()

        case .subscription:
            log("← subscription ack")

        case .cancelling:
            log("← unsubscribe ack")

        case .headerWithFLC:
            handleHeader(payload, seq: msgSeq)

        case .terminatorWithFLC:
            handleTerminator()

        case .dmrAudioFrame:
            handleAudio(payload)

        case .dmrEmbeddedData:
            break

        case .report,
             .busyNotice:
            handleReportNotice(payload)

        case .addressNotice,
             .bindingNotice:
            break

        case .failureCode:
            handleFailureCode(payload)

        case .close:
            fail("master closed session")

        case .authentication:
            break
        }
    }

    private func handleChallenge(_ payload: [UInt8]) {
        guard payload.count == 4 else {
            fail("bad challenge token")
            return
        }
        log("← challenge")
        sendAuth(token: payload)
    }

    private func handleKeepAliveMessage() {
        lastAck = Date()
        if state == .authorising || state == .login {
            becomeRunning()
        }
    }

    private func handleTerminator() {
        if lastHeaderSeq != nil {
            onCallEnd?(currentCallID)
            lastHeaderSeq = nil
        }
    }

    private func handleReportNotice(_ payload: [UInt8]) {
        let text = (String(bytes: payload, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        if !text.isEmpty {
            log("← master: \(text)")
        }
    }

    private func handleFailureCode(_ payload: [UInt8]) {
        log("← failure code \(payload.map { String(format: "%02x", $0) }.joined())", error: true)
    }

    private func handleHeader(_ payload: [UInt8], seq msgSeq: UInt32) {
        guard payload.count >= 9 else {
            return
        }
        let dst = UInt32(payload[3]) << 16 | UInt32(payload[4]) << 8 | UInt32(payload[5])
        let src = UInt32(payload[6]) << 16 | UInt32(payload[7]) << 8 | UInt32(payload[8])
        let isGroup = payload[0] == 0

        // Headers repeat with consecutive sequence numbers; a gap (or the
        // first header after a terminator) marks a new call.
        let isNew: Bool = if let last = lastHeaderSeq {
            msgSeq &- last > 1
        } else {
            true
        }
        lastHeaderSeq = msgSeq

        if isNew, isGroup {
            currentCallID = UInt32.random(in: 1 ... UInt32.max)
            currentDst = dst
            onCallStart?(currentCallID, src, dst)
        }
    }

    private func handleAudio(_ payload: [UInt8]) {
        guard payload.count == 27 else {
            return
        }
        var frames: [[CChar]] = []
        for i in stride(from: 0, to: 27, by: 9) {
            if let frame = VoiceBurst.ambeFrame(Array(payload[i ..< (i + 9)])) {
                frames.append(frame)
            }
        }
        if !frames.isEmpty {
            onAudio?(frames, currentDst)
        }
    }

    // MARK: - Helpers

    private func becomeRunning() {
        state = .running
        log("logged in, pinging every 5s")
        sendSubscriptions()
    }

    private func fail(_ why: String) {
        log(why, error: true)
        timer?.cancel()
        timer = nil
        conn?.cancel()
        conn = nil
        state = .failed(why)
    }

    private func log(_ message: String, error: Bool = false) {
        onLog?(message, error)
    }

    private func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8)])
    }

    private func le32(_ v: UInt32) -> Data {
        Data([
            UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF),
        ])
    }
}
