import Foundation
import Network
import CryptoKit

struct HomebrewConfig {
    var host: String
    var port: UInt16
    var repeaterID: UInt32
    var password: String
    var callsign: String
    var options: String
    var frequency: UInt32 = 438_800_000
    var colorCode: UInt32 = 1
    var location: String = ""
}

enum LinkState: Equatable {
    case idle
    case connecting
    case login
    case authorising
    case configuring
    case options
    case running
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Disconnected"
        case .connecting: return "Connecting"
        case .login: return "Logging in"
        case .authorising: return "Authorising"
        case .configuring: return "Sending config"
        case .options: return "Sending options"
        case .running: return "Connected"
        case .failed(let why): return "Failed: \(why)"
        }
    }
}

// Speaks the MMDVM homebrew repeater protocol
final class HomebrewClient {
    private let config: HomebrewConfig
    private let queue = DispatchQueue(label: "homebrew.net")
    private var conn: NWConnection?
    private var pingTimer: DispatchSourceTimer?
    private var watchdog: DispatchWorkItem?
    private var idBytes: [UInt8]

    private(set) var state: LinkState = .idle {
        didSet { onState?(state) }
    }

    var onState: ((LinkState) -> Void)?
    var onPacket: ((DMRDPacket) -> Void)?
    var onLog: ((String, Bool) -> Void)?

    init(config: HomebrewConfig) {
        self.config = config
        self.idBytes = withUnsafeBytes(of: config.repeaterID.bigEndian, Array.init)
    }

    func connect() {
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            state = .failed("bad port")
            return
        }
        state = .connecting
        log("connecting to \(config.host):\(config.port)")
        let c = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .udp)
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.log("udp socket ready")
                self.sendLogin()
                self.receiveLoop()
            case .failed(let err):
                self.fail(err.localizedDescription)
            case .cancelled:
                self.state = .idle
            default:
                break
            }
        }
        c.start(queue: queue)
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pingTimer?.cancel()
            self.pingTimer = nil
            self.watchdog?.cancel()
            if self.state == .running {
                self.log("→ RPTCL closing link")
                self.send("RPTCL", self.idBytes)
            }
            self.conn?.cancel()
            self.conn = nil
            self.state = .idle
        }
    }

    // MARK: - Outbound

    private func send(_ tag: String, _ body: [UInt8]) {
        var d = Data(tag.utf8)
        d.append(contentsOf: body)
        conn?.send(content: d, completion: .contentProcessed { _ in })
    }

    private func sendLogin() {
        state = .login
        log("→ RPTL login as \(config.repeaterID)")
        send("RPTL", idBytes)
        armWatchdog()
    }

    private func sendAuth(salt: [UInt8]) {
        state = .authorising
        var input = Data(salt)
        input.append(contentsOf: config.password.utf8)
        let digest = SHA256.hash(data: input)
        log("→ RPTK auth response")
        send("RPTK", idBytes + Array(digest))
        armWatchdog()
    }

    private func sendConfig() {
        state = .configuring
        // Field layout mirrors MMDVMHost writeConfig
        let body = pad(config.callsign, 8)
            + String(format: "%09u", config.frequency)
            + String(format: "%09u", config.frequency)
            + String(format: "%02u", 1)
            + String(format: "%02u", config.colorCode)
            + String(format: "%08f", 0.0)
            + String(format: "%09f", 0.0)
            + String(format: "%03d", 0)
            + pad(config.location, 20)
            + pad("DMRMonitor iOS", 19)
            + "4"
            + pad("https://github.com/carrierwave", 124)
            + pad("DMRMonitor-iOS-0.1", 40)
            + pad("DMRMonitor", 40)
        log("→ RPTC config \(config.callsign.trimmingCharacters(in: .whitespaces)) cc\(config.colorCode)")
        send("RPTC", idBytes + Array(body.utf8))
        armWatchdog()
    }

    private func sendOptions() {
        state = .options
        log("→ RPTO \(config.options)")
        send("RPTO", idBytes + Array(config.options.utf8))
        armWatchdog()
    }

    private func sendPing() {
        send("RPTPING", idBytes)
    }

    private func startPing() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.sendPing() }
        t.resume()
        pingTimer = t
    }

    // MARK: - Inbound

    private func receiveLoop() {
        conn?.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data { self.handle(data) }
            if error == nil { self.receiveLoop() }
        }
    }

    private func handle(_ data: Data) {
        guard data.count >= 4 else { return }
        let b = [UInt8](data)

        if hasPrefix(b, "DMRD") {
            if let pkt = DMRDPacket.parse(data) { onPacket?(pkt) }
            return
        }
        if hasPrefix(b, "MSTPONG") { return }
        if hasPrefix(b, "MSTNAK") {
            fail("master refused login")
            return
        }
        if hasPrefix(b, "MSTCL") {
            fail("master closed link")
            return
        }
        if hasPrefix(b, "RPTACK") {
            log("← RPTACK")
            watchdog?.cancel()
            advance(ack: b)
        }
    }

    private func advance(ack: [UInt8]) {
        switch state {
        case .login:
            guard ack.count >= 10 else { return fail("short ack") }
            sendAuth(salt: Array(ack[6..<10]))
        case .authorising:
            sendConfig()
        case .configuring:
            if config.options.isEmpty {
                becomeRunning()
            } else {
                sendOptions()
            }
        case .options:
            becomeRunning()
        default:
            break
        }
    }

    private func becomeRunning() {
        state = .running
        log("logged in, pinging every 5s")
        startPing()
    }

    // MARK: - Helpers

    private func armWatchdog() {
        watchdog?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.fail("no reply from master")
        }
        watchdog = w
        queue.asyncAfter(deadline: .now() + 6, execute: w)
    }

    private func fail(_ why: String) {
        log(why, error: true)
        pingTimer?.cancel()
        pingTimer = nil
        watchdog?.cancel()
        conn?.cancel()
        conn = nil
        state = .failed(why)
    }

    private func log(_ s: String, error: Bool = false) {
        onLog?(s, error)
    }

    private func hasPrefix(_ b: [UInt8], _ tag: String) -> Bool {
        let t = Array(tag.utf8)
        return b.count >= t.count && Array(b[0..<t.count]) == t
    }

    private func pad(_ s: String, _ n: Int) -> String {
        let cut = String(s.prefix(n))
        return cut + String(repeating: " ", count: n - cut.count)
    }
}
