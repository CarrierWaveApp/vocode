import AVFoundation
import Combine
import Foundation

struct HeardEntry: Identifiable, Equatable {
    let id: UInt32 // streamID
    let src: UInt32
    let dst: UInt32
    let slot: Int
    let started: Date
    var ended: Date?
    var callsign: String?
    var note: CallNote?
    // D-STAR: reflector/module label shown where DMR shows the talkgroup,
    // and a marker that src is a callsign hash rather than a DMR ID
    var channel: String?
    var dstar: Bool = false
    // Map coordinates, attached asynchronously from QRZ
    var point: GeoPoint?
    var geoSource: GeoSource?

    var isActive: Bool {
        ended == nil
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let line: String
    let isError: Bool
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published var link: LinkState = .idle
    @Published var heard: [HeardEntry] = []
    /// Ad-hoc mutes for talkgroups not in the configured list
    @Published var muted: Set<UInt32> = []
    // Configured talkgroups silenced via listen state (muted or off)
    private var silenced: Set<UInt32> = []
    private var otpSubscribed: Set<UInt32> = []
    @Published var audioError: String?
    @Published var log: [LogEntry] = []
    @Published var transmitting = false
    @Published var txBursts: [TXBurst] = []

    var mic: MicCapture?
    private var txBatcher: TxBatcher?
    let txMonitor = TxMonitor()
    var monitorOut: AudioOutput?
    var lastHistorySeed = Date.distantPast
    var historyFeed: BrandmeisterLH?
    private var txDst: UInt32 = 0
    var txPending = false

    private var client: HomebrewClient?
    private var rewind: RewindClient?
    var dstarClient: DExtraClient?
    var iaxClient: IAXClient?
    // Invalidates an in-flight AllStar DNS resolution on disconnect/reconnect
    var iaxConnectToken = UUID()
    var allstarStream: UInt32 = 0xA500_0000
    private var scout: MasterScout?
    let pipeline = DecodePipeline()
    private let lookup = CallsignLookup()
    let qrz = QRZLookup()
    // BM map overlay; independent of the DMR link on purpose, so the map
    // works while disconnected — disconnect() must not touch it
    let overlay: OverlayModel
    let notes: CallNotesStore
    let maxHeard = 200
    private let maxLog = 300

    var isConnected: Bool {
        link == .running
    }

    init(notes: CallNotesStore) {
        self.notes = notes
        overlay = OverlayModel(qrz: qrz)
        overlay.log = { [weak self] line, isError in
            self?.appendLog(line, error: isError)
        }
        pipeline.onCallStart = { [weak self] pkt in
            Task { @MainActor in self?.openCall(pkt) }
        }
        pipeline.onCallEnd = { [weak self] stream in
            Task { @MainActor in self?.closeCall(stream) }
        }
    }

    func connect(_ settings: Settings) {
        disconnect()
        if settings.singleTG {
            settings.enforceSingleLive()
        }
        if settings.netMode == "homebrew" {
            connectHomebrew(settings)
        } else if settings.netMode == "dstar" {
            connectDStar(settings)
        } else if settings.netMode == "allstar" {
            connectAllStar(settings)
        } else if settings.autoMaster {
            findMasterThenConnect(settings)
        } else {
            connectRewind(settings)
        }
        Task { await notes.refreshStale() }
        applyQRZ(settings)
        refreshHistory(settings)
    }

    // Probe every BrandMeister master, point the host at the fastest one,
    // then connect. Falls back to the configured host if nothing answers.
    // ("Master" is BrandMeister's own term for its servers.)
    // swiftlint:disable:next inclusive_language
    private func findMasterThenConnect(_ settings: Settings) {
        link = .connecting
        appendLog("probing masters for lowest latency")
        let scout = MasterScout()
        self.scout = scout
        let dmrID = UInt32(settings.dmrID.trimmingCharacters(in: .whitespaces)) ?? 0
        scout.probeAll(dmrID: dmrID) { [weak self] fastest in
            guard let self, self.scout === scout else { return }
            self.scout = nil
            // swiftlint:disable:next inclusive_language
            if let (master, millis) = fastest {
                settings.host = master.host
                settings.otpPort = Int(MasterScout.openTerminalPort)
                self.appendLog("nearest master: \(master.id) \(master.country), \(millis) ms")
            } else {
                self.appendLog("no master reachable, trying \(settings.host)", error: true)
            }
            self.connectRewind(settings)
        }
    }

    func startAudio() {
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
        if transmitting {
            endTransmit()
        }
        if client != nil || rewind != nil || dstarClient != nil || iaxClient != nil {
            appendLog("disconnected")
        }
        scout?.cancelAll()
        scout = nil
        client?.disconnect()
        client = nil
        rewind?.disconnect()
        rewind = nil
        dstarClient?.disconnect()
        dstarClient = nil
        iaxConnectToken = UUID()
        iaxClient?.disconnect()
        iaxClient = nil
        otpSubscribed = []
        pipeline.stopAudio()
        link = .idle
    }

    func clearLog() {
        log.removeAll()
    }

    func appendLog(_ line: String, error: Bool = false) {
        log.insert(LogEntry(line: line, isError: error), at: 0)
        if log.count > maxLog {
            log.removeLast()
        }
    }

    func toggleMute(_ tg: UInt32) {
        if muted.contains(tg) {
            muted.remove(tg)
        } else {
            muted.insert(tg)
        }
        pipeline.setMuted(muted.union(silenced))
    }

    func isSilenced(_ tg: UInt32) -> Bool {
        muted.contains(tg) || silenced.contains(tg)
    }

    /// Push the configured listen states into the audio path and, on OTP,
    /// diff the network subscriptions live.
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
        if iaxClient != nil {
            beginAllStarTransmit(settings)
            return
        }
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
        txMonitor.reset()
        batcher.monitor = txMonitor
        setTransmitAudioSession(true)
        let m = MicCapture()
        m.onFrame = { [txMonitor] pcm in
            txMonitor.appendMic(pcm)
            batcher.submit(pcm)
        }
        m.onFormat = { [weak self] description in
            Task { @MainActor in self?.appendLog("TX mic: \(description)") }
        }
        do {
            try m.start()
        } catch {
            appendLog("microphone failed to start", error: true)
            setTransmitAudioSession(false)
            return
        }
        mic = m
        txBatcher = batcher
        txDst = dst
        rewind.startTransmit(dst: dst)
        transmitting = true
        txBursts.insert(TXBurst(dst: dst, started: Date()), at: 0)
        if txBursts.count > 50 {
            txBursts.removeLast()
        }
    }

    func endTransmit() {
        guard transmitting else { return }
        mic?.stop()
        mic = nil
        txBatcher = nil
        if let iaxClient {
            iaxClient.endTransmit()
        } else {
            rewind?.endTransmit(dst: txDst)
        }
        transmitting = false
        if let index = txBursts.firstIndex(where: { $0.ended == nil }) {
            txBursts[index].ended = Date()
        }
        setTransmitAudioSession(false)
    }

    func clearHeard() {
        heard.removeAll()
    }

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
        if heard.count > maxHeard {
            heard.removeLast()
        }

        Task {
            let call = await lookup.callsign(for: src)
            if let i = heard.firstIndex(where: { $0.id == id }) {
                heard[i].callsign = call
                if let call {
                    heard[i].note = notes.note(for: call)
                }
            }
            if let call {
                await geocode(streamID: id, callsign: call)
            }
        }
    }

    // QRZ geocoding lives in MonitorModel+Geo.swift

    func closeCall(_ stream: UInt32) {
        if let i = heard.firstIndex(where: { $0.id == stream }) {
            heard[i].ended = Date()
        }
    }

    func stationInfo(_ src: UInt32) async -> CallsignInfo? {
        await lookup.info(for: src)
    }
}
