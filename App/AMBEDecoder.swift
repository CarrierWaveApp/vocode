import Foundation
import AVFoundation
import CMBELib

// Wraps mbelib for AMBE+2 3600x2450
final class AMBEDecoder {
    private var ctx = ambe_ctx()
    private let quality: Int32 = 3
    private(set) var lastErrors: Int32 = 0

    init() { reset() }

    func reset() {
        ambe_ctx_init(&ctx)
    }

    // 96-cell frame → 160 float samples
    func decode(_ frame: [CChar]) -> [Float] {
        var out = [Int16](repeating: 0, count: 160)
        frame.withUnsafeBufferPointer { frameBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                lastErrors = ambe_decode_frame(&ctx, frameBuf.baseAddress, outBuf.baseAddress, quality)
            }
        }
        return out.map { Float($0) / 32768.0 }
    }

    // D-STAR variant: 96-cell frame through the 3600x2400 path
    func decode2400(_ frame: [CChar]) -> [Float] {
        var out = [Int16](repeating: 0, count: 160)
        frame.withUnsafeBufferPointer { frameBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                lastErrors = ambe_decode_frame_2400(&ctx, frameBuf.baseAddress, outBuf.baseAddress, quality)
            }
        }
        return out.map { Float($0) / 32768.0 }
    }
}

// 8 kHz mono playback through AVAudioEngine
final class AudioOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
    var gain: Float = 1.0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    func play(_ samples: [Float]) {
        let count = AVAudioFrameCount(samples.count)
        guard count > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let ch = buf.floatChannelData?[0] else { return }
        buf.frameLength = count
        for i in 0..<samples.count {
            ch[i] = max(-1, min(1, samples[i] * gain))
        }
        player.scheduleBuffer(buf)
    }
}
