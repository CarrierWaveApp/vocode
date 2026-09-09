import Foundation

// D-STAR (DExtra/XLX) connection path
extension MonitorModel {
    func connectDStar(_ settings: Settings) {
        guard let cfg = settings.dextraConfig else {
            link = .failed("check settings")
            return
        }
        startAudio()
        let reflector = cfg.host.split(separator: ".").first.map(String.init)?.uppercased() ?? cfg.host
        let channelLabel = "\(reflector) \(cfg.module)"
        let dextra = DExtraClient(config: cfg)
        dextra.onState = { [weak self] newState in
            Task { @MainActor in self?.link = newState }
        }
        dextra.onLog = { [weak self] line, isError in
            Task { @MainActor in self?.appendLog(line, error: isError) }
        }
        dextra.onCallStart = { [weak self] streamID, myCall, _ in
            self?.pipeline.resetDecoder()
            Task { @MainActor in self?.openDStarCall(id: streamID, callsign: myCall, channel: channelLabel) }
        }
        dextra.onAmbe = { [weak self] ambe in
            self?.pipeline.submitDStar(ambe)
        }
        dextra.onCallEnd = { [weak self] streamID in
            Task { @MainActor in self?.closeCall(streamID) }
        }
        dstarClient = dextra
        dextra.connect()
    }

    private func openDStarCall(id: UInt32, callsign call: String, channel: String) {
        for index in heard.indices where heard[index].isActive {
            heard[index].ended = Date()
        }
        var entry = HeardEntry(id: id, src: Self.dstarSrc(call), dst: 0, slot: 0, started: Date())
        entry.callsign = call
        entry.note = notes.note(for: call)
        entry.channel = channel
        entry.dstar = true
        heard.insert(entry, at: 0)
        if heard.count > maxHeard { heard.removeLast() }
        Task { await geocode(streamID: id, callsign: call) }
    }

    // Stable pseudo-ID so timeline lanes key by station; the high bit keeps
    // it clear of real 7-digit DMR IDs and the self-lane sentinel 0
    static func dstarSrc(_ call: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in call.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash | 0x8000_0000
    }
}
