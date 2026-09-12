import AVFoundation
import CMBELib
import Foundation

// MARK: - AMBEDecoder

/// Wraps mbelib for AMBE+2 3600x2450
final class AMBEDecoder {
    // MARK: Lifecycle

    init() {
        reset()
    }

    // MARK: Internal

    private(set) var lastErrors: Int32 = 0

    func reset() {
        ambe_ctx_init(&ctx)
    }

    /// 96-cell frame → 160 float samples
    func decode(_ frame: [CChar]) -> [Float] {
        var out = [Int16](repeating: 0, count: 160)
        frame.withUnsafeBufferPointer { frameBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                lastErrors = ambe_decode_frame(&ctx, frameBuf.baseAddress, outBuf.baseAddress, quality)
            }
        }
        return out.map { Float($0) / 32_768.0 }
    }

    /// D-STAR variant: 96-cell frame through the 3600x2400 path
    func decode2400(_ frame: [CChar]) -> [Float] {
        var out = [Int16](repeating: 0, count: 160)
        frame.withUnsafeBufferPointer { frameBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                lastErrors = ambe_decode_frame_2400(&ctx, frameBuf.baseAddress, outBuf.baseAddress, quality)
            }
        }
        return out.map { Float($0) / 32_768.0 }
    }

    // MARK: Private

    private var ctx = ambe_ctx()
    private let quality: Int32 = 3
}

// MARK: - AudioOutput

/// 8 kHz mono playback through AVAudioEngine
final class AudioOutput {
    // MARK: Lifecycle

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // The engine stops itself when the output route changes (e.g. Bluetooth
        // headphones connect or disconnect); restart it so audio keeps flowing.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, running, !self.engine.isRunning else {
                return
            }
            try? engine.start()
            player.play()
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    // MARK: Internal

    var gain: Float = 1.0

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback, not .playAndRecord: playback routes to Bluetooth A2DP
        // automatically at full quality. Under .playAndRecord, a device
        // supporting both profiles (e.g. AirPods Max) gets routed to HFP,
        // whose SCO link tends to come up silent when nothing records.
        // Transmit flips the session to .playAndRecord for its duration.
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        try engine.start()
        player.play()
        running = true
    }

    func stop() {
        running = false
        player.stop()
        engine.stop()
    }

    func play(_ samples: [Float]) {
        let count = AVAudioFrameCount(samples.count)
        guard count > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let ch = buf.floatChannelData?[0]
        else {
            return
        }
        buf.frameLength = count
        for i in 0 ..< samples.count {
            ch[i] = max(-1, min(1, samples[i] * gain))
        }
        player.scheduleBuffer(buf)
    }

    // MARK: Private

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
    private var running = false
    private var configObserver: NSObjectProtocol?
}
