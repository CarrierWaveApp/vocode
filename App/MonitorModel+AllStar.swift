import AVFoundation
import Foundation

/// AllStar (IAX2) connection and transmit paths
extension MonitorModel {
    func connectAllStar(_ settings: Settings) {
        guard var cfg = settings.allstarConfig else {
            link = .failed("check settings")
            return
        }
        startAudio()
        link = .connecting
        appendLog("resolving node \(cfg.targetNode)")
        let token = UUID()
        iaxConnectToken = token
        Task { @MainActor in
            let addr = await ASLDirectory.resolve(node: cfg.targetNode)
            guard iaxConnectToken == token else {
                return
            }
            cfg.host = addr.host
            cfg.port = addr.port
            startIAX(cfg)
        }
    }

    private func startIAX(_ cfg: IAXConfig) {
        let target = cfg.targetNode
        let iax = IAXClient(config: cfg)
        iax.onState = { [weak self] newState in
            Task { @MainActor in self?.link = newState }
        }
        iax.onLog = { [weak self] line, isError in
            Task { @MainActor in self?.appendLog(line, error: isError) }
        }
        iax.onRemoteKey = { [weak self] keyed in
            Task { @MainActor in
                if keyed {
                    self?.openAllStarCall(target: target)
                } else {
                    self?.closeCall(self?.allstarStream ?? 0)
                }
            }
        }
        iax.onAudio = { [weak self] pcm in
            self?.pipeline.submitPCM(pcm)
        }
        iaxClient = iax
        iax.connect()
    }

    /// One heard entry per remote key-up. AllStar is analog and carries no
    /// per-talker identity, so entries show the linked node itself.
    private func openAllStarCall(target: String) {
        for index in heard.indices where heard[index].isActive {
            heard[index].ended = Date()
        }
        allstarStream &+= 1
        let call = ASLDirectory.shared.node(forNumber: target)?.callsign ?? "Node \(target)"
        var entry = HeardEntry(id: allstarStream, src: Self.dstarSrc("ASL" + target),
                               dst: 0, slot: 0, started: Date())
        entry.callsign = call
        entry.note = notes.note(for: call)
        entry.channel = "Node \(target)"
        entry.dstar = true
        heard.insert(entry, at: 0)
        if heard.count > maxHeard {
            heard.removeLast()
        }
        Task { await geocode(streamID: entry.id, callsign: call) }
    }

    func beginAllStarTransmit(_ settings: Settings) {
        guard !transmitting, !txPending, isConnected else {
            return
        }
        txPending = true
        Task { @MainActor in
            defer { txPending = false }
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                appendLog("microphone permission denied", error: true)
                return
            }
            guard !transmitting, let iax = iaxClient, isConnected else {
                return
            }
            startAllStarTx(iax, node: settings.aslTarget)
        }
    }

    /// Straight PCM to µ-law, no vocoder: mic frames go to the IAX client
    /// as-is and keying is implied by audio presence
    private func startAllStarTx(_ iax: IAXClient, node: String) {
        setTransmitAudioSession(true)
        txMonitor.reset()
        let capture = MicCapture()
        capture.onFrame = { [weak iax, txMonitor] pcm in
            txMonitor.appendMic(pcm)
            iax?.sendVoice(pcm)
        }
        capture.onFormat = { [weak self] description in
            Task { @MainActor in self?.appendLog("TX mic: \(description)") }
        }
        do {
            try capture.start()
        } catch {
            appendLog("microphone failed to start", error: true)
            setTransmitAudioSession(false)
            return
        }
        mic = capture
        iax.startTransmit()
        transmitting = true
        txBursts.insert(TXBurst(dst: 0, started: Date(), channel: "Node \(node)"), at: 0)
        if txBursts.count > 50 {
            txBursts.removeLast()
        }
    }
}
