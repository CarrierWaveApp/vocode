import Foundation
import Combine
import AVFoundation

struct HeardEntry: Identifiable, Equatable {
    let id: UInt32          // streamID
    let src: UInt32
    let dst: UInt32
    let slot: Int
    let started: Date
    var ended: Date?
    var callsign: String?
    var note: CallNote?

    var isActive: Bool { ended == nil }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let line: String
    let isError: Bool
}

// Decode path, runs off the main thread
final class DecodePipeline {
    private let decoder = AMBEDecoder()
    private let audio = AudioOutput()
    private let queue = DispatchQueue(label: "dmr.decode")
    private let lock = NSLock()
    private var muted: Set<UInt32> = []
    private var currentStream: UInt32 = 0

    var onCallStart: ((DMRDPacket) -> Void)?
    var onCallEnd: ((UInt32) -> Void)?

    func startAudio() throws { try audio.start() }
    func stopAudio() { audio.stop() }

    func setMuted(_ set: Set<UInt32>) {
        lock.withLock { muted = set }
    }

    func submit(_ pkt: DMRDPacket) {
        queue.async { [self] in handle(pkt) }
    }

    // Open Terminal path: frames arrive already extracted and deinterleaved
    func submitAmbe(_ frames: [[CChar]], dst: UInt32) {
        queue.async { [self] in
            if lock.withLock({ muted.contains(dst) }) { return }
            var pcm: [Float] = []
            pcm.reserveCapacity(480)
            for frame in frames {
                pcm.append(contentsOf: decoder.decode(frame))
            }
            audio.play(pcm)
        }
    }

    func resetDecoder() {
        queue.async { [self] in decoder.reset() }
    }

    private func handle(_ pkt: DMRDPacket) {
        guard pkt.isGroup else { return }

        if pkt.streamID != currentStream {
            currentStream = pkt.streamID
            decoder.reset()
            onCallStart?(pkt)
        }

        if pkt.frameType == .dataSync && pkt.dataType == .terminator {
            onCallEnd?(pkt.streamID)
            return
        }

        guard pkt.isVoice, let burst = VoiceBurst(pkt.payload) else { return }
        if lock.withLock({ muted.contains(pkt.dst) }) { return }

        var pcm: [Float] = []
        pcm.reserveCapacity(480)
        for frame in burst.ambeFrames() {
            pcm.append(contentsOf: decoder.decode(frame))
        }
        audio.play(pcm)
    }
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published var link: LinkState = .idle
    @Published var heard: [HeardEntry] = []
    // Ad-hoc mutes for talkgroups not in the configured list
    @Published var muted: Set<UInt32> = []
    // Configured talkgroups silenced via listen state (muted or off)
    private var silenced: Set<UInt32> = []
    private var otpSubscribed: Set<UInt32> = []
    @Published var audioError: String?
    @Published var log: [LogEntry] = []
    @Published var transmitting = false

    private var mic: MicCapture?
    private var txBatcher: TxBatcher?
    private var txDst: UInt32 = 0
    private var txPending = false

    private var client: HomebrewClient?
    private var rewind: RewindClient?
    private let pipeline = DecodePipeline()
    private let lookup = CallsignLookup()
    private let notes: CallNotesStore
    private let maxHeard = 200
    private let maxLog = 300

    var isConnected: Bool { link == .running }

    init(notes: CallNotesStore) {
        self.notes = notes
        pipeline.onCallStart = { [weak self] pkt in
            Task { @MainActor in self?.openCall(pkt) }
        }
        pipeline.onCallEnd = { [weak self] stream in
            Task { @MainActor in self?.closeCall(stream) }
        }
    }

    func connect(_ settings: Settings) {
        disconnect()
        if settings.netMode == "homebrew" {
            connectHomebrew(settings)
        } else {
            connectRewind(settings)
        }
        Task { await notes.refreshStale() }
    }

    private func startAudio() {
        do {
            try pipeline.startAudio()
            audioError = nil
        } catch {
            audioError = "Audio failed to start"
            appendLog("audio failed to start", error: true)
        }
    }

    private func connectHomebrew(_ settings: Settings) {
        guard let cfg = settings.homebrewConfig else {
            link = .failed("check settings")
            return
        }
        startAudio()
        let c = HomebrewClient(config: cfg)
        c.onState = { [weak self] st in
            Task { @MainActor in self?.link = st }
        }
        c.onPacket = { [weak self] pkt in
            self?.pipeline.submit(pkt)
        }
        c.onLog = { [weak self] line, isError in
            Task { @MainActor in self?.appendLog(line, error: isError) }
        }
        client = c
        c.connect()
    }

    private func connectRewind(_ settings: Settings) {
        guard let cfg = settings.rewindConfig else {
            link = .failed("check settings")
            return
        }
        if cfg.talkgroups.isEmpty {
            appendLog("no talkgroups configured, nothing to subscribe", error: true)
        }
        startAudio()
        let c = RewindClient(config: cfg)
        c.onState = { [weak self] st in
            Task { @MainActor in self?.link = st }
        }
        c.onLog = { [weak self] line, isError in
            Task { @MainActor in self?.appendLog(line, error: isError) }
        }
        c.onCallStart = { [weak self] callID, src, dst in
            self?.pipeline.resetDecoder()
            Task { @MainActor in self?.openCall(id: callID, src: src, dst: dst, slot: 0) }
        }
        c.onAudio = { [weak self] frames, dst in
            self?.pipeline.submitAmbe(frames, dst: dst)
        }
        c.onCallEnd = { [weak self] callID in
            Task { @MainActor in self?.closeCall(callID) }
        }
        rewind = c
        otpSubscribed = Set(cfg.talkgroups)
        c.connect()
        applyListenStates(settings)
    }

    func disconnect() {
        if transmitting { endTransmit() }
        if client != nil || rewind != nil { appendLog("disconnected") }
        client?.disconnect()
        client = nil
        rewind?.disconnect()
        rewind = nil
        otpSubscribed = []
        pipeline.stopAudio()
        link = .idle
    }

    func clearLog() { log.removeAll() }

    private func appendLog(_ line: String, error: Bool = false) {
        log.insert(LogEntry(line: line, isError: error), at: 0)
        if log.count > maxLog { log.removeLast() }
    }

    func toggleMute(_ tg: UInt32) {
        if muted.contains(tg) { muted.remove(tg) } else { muted.insert(tg) }
        pipeline.setMuted(muted.union(silenced))
    }

    func isSilenced(_ tg: UInt32) -> Bool {
        muted.contains(tg) || silenced.contains(tg)
    }

    // Push the configured listen states into the audio path and, on OTP,
    // diff the network subscriptions live.
    func applyListenStates(_ settings: Settings) {
        silenced = settings.silencedTalkgroups
        pipeline.setMuted(muted.union(silenced))
        if let rewind {
            let desired = Set(settings.activeTalkgroups)
            for tg in desired.subtracting(otpSubscribed) {
                rewind.setSubscription(tg, active: true)
            }
            for tg in otpSubscribed.subtracting(desired) {
                rewind.setSubscription(tg, active: false)
            }
            otpSubscribed = desired
        }
    }

    // MARK: - Transmit

    func beginTransmit(_ settings: Settings) {
        guard !transmitting, !txPending, rewind != nil, isConnected,
              let target = settings.txTarget, target.listen == .live else { return }
        txPending = true
        Task { @MainActor in
            defer { txPending = false }
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                appendLog("microphone permission denied", error: true)
                return
            }
            guard !transmitting, let rewind, isConnected else { return }
            startTx(rewind: rewind, dst: target.tg)
        }
    }

    private func startTx(rewind: RewindClient, dst: UInt32) {
        guard let enc = AMBEEncoder() else {
            appendLog("AMBE encoder init failed", error: true)
            return
        }
        let batcher = TxBatcher(encoder: enc) { [weak rewind] payload in
            rewind?.sendTransmitAudio(payload)
        }
        let m = MicCapture()
        m.onFrame = { pcm in batcher.submit(pcm) }
        do {
            try m.start()
        } catch {
            appendLog("microphone failed to start", error: true)
            return
        }
        mic = m
        txBatcher = batcher
        txDst = dst
        rewind.startTransmit(dst: dst)
        transmitting = true
    }

    func endTransmit() {
        guard transmitting else { return }
        mic?.stop()
        mic = nil
        txBatcher = nil
        rewind?.endTransmit(dst: txDst)
        transmitting = false
    }

    func clearHeard() { heard.removeAll() }

    private func openCall(_ pkt: DMRDPacket) {
        openCall(id: pkt.streamID, src: pkt.src, dst: pkt.dst, slot: pkt.slot)
    }

    private func openCall(id: UInt32, src: UInt32, dst: UInt32, slot: Int) {
        for i in heard.indices where heard[i].isActive {
            heard[i].ended = Date()
        }
        let entry = HeardEntry(
            id: id, src: src, dst: dst,
            slot: slot, started: Date()
        )
        heard.insert(entry, at: 0)
        if heard.count > maxHeard { heard.removeLast() }

        Task {
            let call = await lookup.callsign(for: src)
            if let i = heard.firstIndex(where: { $0.id == id }) {
                heard[i].callsign = call
                if let call { heard[i].note = notes.note(for: call) }
            }
        }
    }

    private func closeCall(_ stream: UInt32) {
        if let i = heard.firstIndex(where: { $0.id == stream }) {
            heard[i].ended = Date()
        }
    }
}

// radioid.net lookup with cache
actor CallsignLookup {
    private var cache: [UInt32: String] = [:]

    func callsign(for id: UInt32) async -> String? {
        if let hit = cache[id] { return hit }
        guard let url = URL(string: "https://radioid.net/api/dmr/user/?id=\(id)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let call = results.first?["callsign"] as? String else { return nil }
        cache[id] = call
        return call
    }
}
