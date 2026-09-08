import Foundation

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
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
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

    private func open() {
        teardown()
        guard !talkgroups.isEmpty else {
            state = .failed("no talkgroup")
            return
        }
        let urlString = "wss://api.brandmeister.network/lh/socket.io/?EIO=4&transport=websocket"
        guard let url = URL(string: urlString) else { return }
        state = .connecting
        let sess = URLSession(configuration: .default)
        session = sess
        let socket = sess.webSocketTask(with: url)
        task = socket
        lastActivity = Date()
        socket.resume()
        receive(on: socket)
        startTimers()
    }

    private func teardown() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
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
        state = .connecting
        onLog?("BM feed reconnecting in \(Int(delay))s", false)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.open()
        }
    }

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard socket === self.task, !self.stopped else { return }
                switch result {
                case .failure(let error):
                    self.onLog?("BM feed: \(error.localizedDescription)", true)
                    self.scheduleReconnect()
                case .success(let message):
                    self.lastActivity = Date()
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: socket)
                }
            }
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

    private func process(_ call: [String: Any]) {
        guard let dst = number(call["DestinationID"]), talkgroups.contains(dst),
              let src = number(call["SourceID"]),
              let sourceCall = call["SourceCall"] as? String, !sourceCall.isEmpty
        else { return }
        let event = call["Event"] as? String ?? ""
        let stopTime = number(call["Stop"]) ?? 0
        let name = (call["SourceName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        pending.append(BMCall(
            sourceID: src,
            sourceCall: sourceCall.uppercased(),
            sourceName: name,
            destinationID: dst,
            active: event != "Session-Stop" && stopTime == 0,
            time: Date()
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
        task?.send(.string(text)) { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                guard !self.stopped else { return }
                self.onLog?("BM send failed: \(error.localizedDescription)", true)
            }
        }
    }
}
