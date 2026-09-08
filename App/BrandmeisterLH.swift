import Foundation
import Network

// One call event from the BrandMeister last-heard stream
struct BMCall: Equatable {
    let sourceID: UInt32
    let sourceCall: String
    let sourceName: String?
    let destinationID: UInt32
    let active: Bool
    let time: Date
}

// Minimal Engine.IO v4 / Socket.IO client for BrandMeister's last-heard
// feed. The raw stream is all of BrandMeister; events are filtered by
// talkgroup on the socket queue before delivery.
final class BrandmeisterLH {
    var onState: ((LinkState) -> Void)?
    var onLog: ((String, Bool) -> Void)?
    var onCalls: (([BMCall]) -> Void)?

    private let queue = DispatchQueue(label: "bm.lh")
    private var conn: NWConnection?
    private var talkgroups: Set<UInt32>
    private var stopped = false
    private var attempts = 0
    private var pending: [BMCall] = []
    private var flusher: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?
    private var lastActivity = Date()
    private var pingInterval: TimeInterval = 25
    private var pingTimeout: TimeInterval = 20
    private var loggedFirstFrame = false

    private var state: LinkState = .idle {
        didSet { if state != oldValue { onState?(state) } }
    }

    init(talkgroups: Set<UInt32>) {
        self.talkgroups = talkgroups
    }

    func connect() {
        queue.async {
            self.stopped = false
            self.attempts = 0
            self.open()
        }
    }

    func disconnect() {
        queue.async {
            self.stopped = true
            self.teardown()
            self.state = .idle
        }
    }

    // The feed is room-based (join-only, no leave), so a talkgroup change
    // means a reconnect
    func setTalkgroups(_ tgs: Set<UInt32>) {
        queue.async {
            guard tgs != self.talkgroups else { return }
            self.talkgroups = tgs
            guard !self.stopped else { return }
            self.attempts = 0
            self.open()
        }
    }

    // MARK: - Connection

    // Network.framework, not URLSessionWebSocketTask: the server negotiates
    // HTTP/2, and iOS's websocket task then attempts RFC 8441 websockets-
    // over-h2, which BM's socket.io backend rejects ("bad response from
    // the server"). NWProtocolWebSocket always does an HTTP/1.1 upgrade.
    private func open() {
        teardown()
        guard !talkgroups.isEmpty else {
            state = .failed("no talkgroup")
            return
        }
        let urlString = "wss://api.brandmeister.network/lh/socket.io/?EIO=4&transport=websocket"
        guard let url = URL(string: urlString) else { return }
        state = .connecting
        let params = NWParameters.tls
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        let socket = NWConnection(to: .url(url), using: params)
        conn = socket
        lastActivity = Date()
        socket.stateUpdateHandler = { [weak self] update in
            guard let self, socket === self.conn, !self.stopped else { return }
            switch update {
            case .failed(let error):
                self.onLog?("BM feed: \(error.localizedDescription)", true)
                self.state = .failed(error.localizedDescription)
                self.scheduleReconnect()
            case .waiting(let error):
                self.onLog?("BM feed waiting: \(error.localizedDescription)", true)
            default:
                break
            }
        }
        socket.start(queue: queue)
        receive(on: socket)
        startTimers()
    }

    private func teardown() {
        conn?.stateUpdateHandler = nil
        conn?.cancel()
        conn = nil
        flusher?.cancel()
        flusher = nil
        watchdog?.cancel()
        watchdog = nil
        pending = []
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        teardown()
        attempts += 1
        let base = min(30.0, pow(2.0, Double(attempts - 1)))
        let jitter = Double.random(in: 0.8...1.2)
        let delay = base * jitter
        // Keep any .failed reason visible during the backoff wait;
        // open() flips to .connecting when the retry actually starts
        onLog?("BM feed reconnecting in \(Int(delay))s", false)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.open()
        }
    }

    private func receive(on socket: NWConnection) {
        socket.receiveMessage { [weak self] data, _, _, error in
            guard let self, socket === self.conn, !self.stopped else { return }
            if let error {
                self.onLog?("BM feed: \(error.localizedDescription)", true)
                // Surface the failure; otherwise a connect-failure loop
                // re-sets .connecting, the didSet dedup swallows it, and
                // the UI shows "connecting" forever with no reason
                self.state = .failed(error.localizedDescription)
                self.scheduleReconnect()
                return
            }
            self.lastActivity = Date()
            if let data, let text = String(data: data, encoding: .utf8) {
                self.handle(text)
            }
            self.receive(on: socket)
        }
    }

    // MARK: - Engine.IO framing

    private func handle(_ text: String) {
        if text.hasPrefix("0") {
            handleOpen(text)
        } else if text.hasPrefix("40") {
            state = .running
            attempts = 0
            // Room-based server: subscribe to each talkgroup's room
            for group in talkgroups {
                send("42[\"join\",\"dst_\(group)\"]")
            }
            requestBacklog()
        } else if text == "2" {
            send("3")
        } else if text.hasPrefix("42") {
            handleEvent(text)
        } else if text == "1" || text.hasPrefix("41") {
            onLog?("BM feed closed by server", false)
            scheduleReconnect()
        }
    }

    private func handleOpen(_ text: String) {
        if let data = text.dropFirst().data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let millis = json["pingInterval"] as? Double { pingInterval = millis / 1000 }
            if let millis = json["pingTimeout"] as? Double { pingTimeout = millis / 1000 }
        }
        send("40")
    }

    private func handleEvent(_ text: String) {
        guard let bracket = text.firstIndex(of: "["),
              let data = String(text[bracket...]).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2, (array[0] as? String) == "mqtt"
        else { return }
        if !loggedFirstFrame {
            loggedFirstFrame = true
            onLog?("BM first frame: \(String(text.prefix(300)))", false)
        }
        // Event data is {"topic": ..., "payload": "<json string>"}, but both
        // the wrapper and the payload have shipped as dicts or JSON strings
        var payload: Any = array[1]
        if let wrapper = unwrap(payload) as? [String: Any], let inner = wrapper["payload"] {
            payload = inner
        }
        guard let call = unwrap(payload) as? [String: Any] else { return }
        process(call)
    }

    private func unwrap(_ value: Any) -> Any {
        guard let text = value as? String, let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return value }
        return json
    }

    // History replay: same mqtt events the live stream uses, tagged
    // "LH-Startup", terminated by searchHouseComplete. This is the only
    // history API BrandMeister has — there is no REST endpoint for it.
    private func requestBacklog() {
        let rules = talkgroups.map { group in
            ["id": "DestinationID", "operator": "equal", "value": Int(group)] as [String: Any]
        }
        let request: [String: Any] = [
            "query": ["condition": "OR", "rules": rules],
            "amount": 25
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8) else { return }
        send("42[\"searchHouse\",\(json)]")
    }

    private func process(_ call: [String: Any]) {
        guard let dst = number(call["DestinationID"]), talkgroups.contains(dst),
              let src = number(call["SourceID"]),
              let sourceCall = call["SourceCall"] as? String, !sourceCall.isEmpty
        else { return }
        let event = call["Event"] as? String ?? ""
        let startTime = number(call["Start"]) ?? 0
        let stopTime = number(call["Stop"]) ?? 0
        let name = (call["SourceName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Server timestamps, so backlog rows carry their real age
        let stamp = stopTime > 0 ? stopTime : startTime
        pending.append(BMCall(
            sourceID: src,
            sourceCall: sourceCall.uppercased(),
            sourceName: name,
            destinationID: dst,
            active: event != "Session-Stop" && stopTime == 0,
            time: stamp > 0 ? Date(timeIntervalSince1970: TimeInterval(stamp)) : Date()
        ))
    }

    // BM ships numerics as Int, Double, or String depending on the day
    private func number(_ value: Any?) -> UInt32? {
        if let num = value as? Int, num >= 0, num <= UInt32.max { return UInt32(num) }
        if let num = value as? Double, num >= 0, num <= Double(UInt32.max) { return UInt32(num) }
        if let str = value as? String { return UInt32(str) }
        return nil
    }

    // MARK: - Timers

    private func startTimers() {
        let flushTimer = DispatchSource.makeTimerSource(queue: queue)
        flushTimer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        flushTimer.setEventHandler { [weak self] in
            guard let self, !self.pending.isEmpty else { return }
            let batch = self.pending
            self.pending = []
            self.onCalls?(batch)
        }
        flushTimer.resume()
        flusher = flushTimer

        let watchTimer = DispatchSource.makeTimerSource(queue: queue)
        watchTimer.schedule(deadline: .now() + 5, repeating: 5)
        watchTimer.setEventHandler { [weak self] in
            guard let self, !self.stopped else { return }
            if Date().timeIntervalSince(self.lastActivity) > self.pingInterval + self.pingTimeout {
                self.onLog?("BM feed stalled, reconnecting", true)
                self.scheduleReconnect()
            }
        }
        watchTimer.resume()
        watchdog = watchTimer
    }

    private func send(_ text: String) {
        guard let conn else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        conn.send(
            content: text.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard let self, let error, !self.stopped else { return }
                self.onLog?("BM send failed: \(error.localizedDescription)", true)
            }
        )
    }
}
