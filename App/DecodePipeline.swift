import Foundation

/// Decode path, runs off the main thread
final class DecodePipeline {
    private let decoder = AMBEDecoder()
    private let audio = AudioOutput()
    private let queue = DispatchQueue(label: "dmr.decode")
    private let lock = NSLock()
    private var muted: Set<UInt32> = []
    private var currentStream: UInt32 = 0

    var onCallStart: ((DMRDPacket) -> Void)?
    var onCallEnd: ((UInt32) -> Void)?

    func startAudio() throws {
        try audio.start()
    }

    func stopAudio() {
        audio.stop()
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
            }
            audio.play(pcm)
        }
    }

    /// D-STAR path: one 9-byte AMBE frame per 20 ms network packet
    func submitDStar(_ ambe: [UInt8]) {
        queue.async { [self] in
            audio.play(decoder.decode2400(DStarFrame.cells(from: ambe)))
        }
    }

    /// AllStar path: already-decoded 8 kHz PCM, no vocoder involved
    func submitPCM(_ pcm: [Float]) {
        queue.async { [self] in
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

        if pkt.frameType == .dataSync, pkt.dataType == .terminator {
            onCallEnd?(pkt.streamID)
            return
        }

        guard pkt.isVoice, let burst = VoiceBurst(pkt.payload) else { return }
        if lock.withLock({ muted.contains(pkt.dst) }) {
            return
        }

        var pcm: [Float] = []
        pcm.reserveCapacity(480)
        for frame in burst.ambeFrames() {
            pcm.append(contentsOf: decoder.decode(frame))
        }
        audio.play(pcm)
    }
}
