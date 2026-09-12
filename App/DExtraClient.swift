import Foundation
import Network

struct DExtraConfig {
    var host: String
    var port: UInt16 = 30001
    var callsign: String
    var module: Character
}

// Speaks the DExtra (XRF) linking protocol, which XLX reflectors accept.
// Receive-only: links to one reflector module and hands 9-byte AMBE
// frames up. Voice arrives as DSVT packets: 56-byte headers carrying the
// callsign fields, 27-byte voice frames carrying AMBE plus slow data.
final class DExtraClient {
    private let config: DExtraConfig
    private let queue = DispatchQueue(label: "dextra.net")
    private var conn: NWConnection?
    private var timer: DispatchSourceTimer?
    private var lastHeard = Date()

    private(set) var state: LinkState = .idle {
        didSet { onState?(state) }
    }

    var onState: ((LinkState) -> Void)?
    var onLog: ((String, Bool) -> Void)?
    var onCallStart: ((_ streamID: UInt32, _ my: String, _ ur: String) -> Void)?
    var onAmbe: ((_ ambe: [UInt8]) -> Void)?
    var onCallEnd: ((_ streamID: UInt32) -> Void)?

    init(config: DExtraConfig) {
        self.config = config
    }

    func connect() {
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            state = .failed("bad port")
            return
        }
        state = .connecting
        log("connecting to \(config.host):\(config.port) (dextra)")
        let connection = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .udp)
        conn = connection
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.log("udp socket ready")
                self.state = .login
                self.lastHeard = Date()
                self.log("→ link \(self.config.module)")
                self.sendLink(module: self.config.module)
                self.startTimer()
                self.receiveLoop()
            case let .failed(err):
                self.fail(err.localizedDescription)
            case .cancelled:
                self.state = .idle
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            if self.state == .running || self.state == .login {
                self.log("→ unlink")
                self.sendLink(module: " ")
            }
            self.conn?.cancel()
            self.conn = nil
            self.state = .idle
        }
    }

    // MARK: - Outbound

    private var paddedCall: [UInt8] {
        Array(config.callsign.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0).utf8)
    }

    /// Link request: callsign, our module letter, reflector module, NUL.
    /// Module " " means unlink.
    private func sendLink(module: Character) {
        var pkt = paddedCall
        pkt.append(UInt8(ascii: "D"))
        pkt.append(module.asciiValue ?? UInt8(ascii: " "))
        pkt.append(0)
        conn?.send(content: Data(pkt), completion: .contentProcessed { _ in })
    }

    private func sendKeepAlive() {
        var pkt = paddedCall
        pkt.append(0)
        conn?.send(content: Data(pkt), completion: .contentProcessed { _ in })
    }

    private func startTimer() {
        let timerSource = DispatchSource.makeTimerSource(queue: queue)
        timerSource.schedule(deadline: .now() + 3, repeating: 3)
        timerSource.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendKeepAlive()
            let quiet = Date().timeIntervalSince(self.lastHeard)
            if self.state == .login, quiet > 8 {
                self.fail("no answer from reflector")
            } else if self.state == .running, quiet > 40 {
                self.fail("link lost")
            }
        }
        timerSource.resume()
        timer = timerSource
    }

    // MARK: - Inbound

    private func receiveLoop() {
        conn?.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data {
                self.handle(data)
            }
            if error == nil {
                self.receiveLoop()
            }
        }
    }

    private func handle(_ data: Data) {
        lastHeard = Date()
        if data.count == 14 {
            if data.range(of: Data("ACK".utf8)) != nil {
                if state != .running {
                    state = .running
                    log("linked to \(config.host) module \(config.module)")
                }
            } else if data.range(of: Data("NAK".utf8)) != nil {
                fail("link refused")
            }
            return
        }
        guard data.count >= 27, data.prefix(4) == Data("DSVT".utf8) else { return }
        let streamID = UInt32(data[12]) << 8 | UInt32(data[13])
        if data[4] == 0x10, data.count >= 56 {
            let myCall = field(data, 42, 8)
            let urCall = field(data, 34, 8)
            log("call from \(myCall) → \(urCall)")
            onCallStart?(streamID, myCall, urCall)
        } else if data[4] == 0x20 {
            if data[14] & 0x40 != 0 {
                onCallEnd?(streamID)
            } else {
                onAmbe?(Array(data[15 ..< 24]))
            }
        }
    }

    private func field(_ data: Data, _ offset: Int, _ length: Int) -> String {
        let bytes = data[data.startIndex + offset ..< data.startIndex + offset + length]
        return (String(bytes: bytes, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Plumbing

    private func fail(_ why: String) {
        log(why, error: true)
        timer?.cancel()
        timer = nil
        conn?.cancel()
        conn = nil
        state = .failed(why)
    }

    private func log(_ line: String, error: Bool = false) {
        onLog?(line, error)
    }
}
