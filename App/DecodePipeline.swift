import Foundation

/// Decode path, runs off the main thread
final class DecodePipeline {
    // MARK: Internal

    var onCallStart: ((DMRDPacket) -> Void)?
    var onCallEnd: ((UInt32) -> Void)?
    /// Per-call decode summary: voice frames, frames mbelib flagged as
    /// damaged (it repeats the last good frame, then mutes), audio status
    var onCallStats: ((_ frames: Int, _ damaged: Int, _ status: String) -> Void)?

    var onAudioRestart: ((_ reason: String, _ error: Error?) -> Void)? {
        get { audio.onRestart }
        set { audio.onRestart = newValue }
    }

    func startAudio() throws {
        try audio.start()
    }

    func stopAudio() {
        audio.stop()
    }

    /// See `AudioOutput.resume`; called when the app returns to the foreground
    func resumeAudio() {
        audio.resume(reason: "app became active")
    }

    func setMuted(_ set: Set<UInt32>) {
        lock.withLock { muted = set }
    }

    func submit(_ pkt: DMRDPacket) {
        queue.async { [self] in handle(pkt) }
    }

    /// Open Terminal path: frames arrive already extracted and deinterleaved
    func submitAmbe(_ frames: [[CChar]], dst: UInt32) {
        queue.async { [self] in
            if lock.withLock({ muted.contains(dst) }) {
                return
            }
            var pcm: [Float] = []
            pcm.reserveCapacity(480)
            for frame in frames {
                pcm.append(contentsOf: decoder.decode(frame))
                count(decoder.lastErrors)
            }
            audio.play(pcm)
        }
    }

    /// D-STAR path: one 9-byte AMBE frame per 20 ms network packet
    func submitDStar(_ ambe: [UInt8]) {
        queue.async { [self] in
            audio.play(decoder.decode2400(DStarFrame.cells(from: ambe)))
            count(decoder.lastErrors)
        }
    }

    /// AllStar path: already-decoded 8 kHz PCM, no vocoder involved
    func submitPCM(_ pcm: [Float]) {
        queue.async { [self] in
            audio.play(pcm)
        }
    }

    /// Call start on the Open Terminal and D-STAR paths
    func resetDecoder() {
        queue.async { [self] in
            flushStatsLocked()
            decoder.reset()
            audio.resume(reason: "call start")
        }
    }

    /// Call end: emit the decode summary for the call that just finished
    func flushStats() {
        queue.async { [self] in flushStatsLocked() }
    }

    // MARK: Private

    private let decoder = AMBEDecoder()
    private let audio = AudioOutput()
    private let queue = DispatchQueue(label: "dmr.decode")
    private let lock = NSLock()
    private var muted: Set<UInt32> = []
    private var currentStream: UInt32 = 0
    private var statFrames = 0
    private var statDamaged = 0

    /// Decode-queue only
    private func count(_ errors: Int32) {
        statFrames += 1
        // mbelib's threshold: above 3 uncorrectable errors it repeats the
        // previous frame's parameters, and after 4 repeats synthesizes silence
        if errors > 3 {
            statDamaged += 1
        }
    }

    /// Decode-queue only
    private func flushStatsLocked() {
        guard statFrames > 0 else {
            return
        }
        onCallStats?(statFrames, statDamaged, audio.status)
        statFrames = 0
        statDamaged = 0
    }

    private func handle(_ pkt: DMRDPacket) {
        guard pkt.isGroup else {
            return
        }

        if pkt.streamID != currentStream {
            currentStream = pkt.streamID
            flushStatsLocked()
            decoder.reset()
            audio.resume(reason: "call start")
            onCallStart?(pkt)
        }

        if pkt.frameType == .dataSync, pkt.dataType == .terminator {
            flushStatsLocked()
            onCallEnd?(pkt.streamID)
            return
        }

        guard pkt.isVoice, let burst = VoiceBurst(pkt.payload) else {
            return
        }
        if lock.withLock({ muted.contains(pkt.dst) }) {
            return
        }

        var pcm: [Float] = []
        pcm.reserveCapacity(480)
        for frame in burst.ambeFrames() {
            pcm.append(contentsOf: decoder.decode(frame))
            count(decoder.lastErrors)
        }
        audio.play(pcm)
    }
}
