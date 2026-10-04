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
        wire()
        let center = NotificationCenter.default
        // The engine stops itself when the output route changes (e.g. Bluetooth
        // headphones connect or disconnect, or the TX session flip); restart it
        // so audio keeps flowing.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, (note.object as? AVAudioEngine) === engine else {
                return
            }
            resume(reason: "route change")
        })
        // A phone call, Siri, an alarm, another app taking the session, or the
        // app being suspended all stop the engine WITHOUT a configuration
        // change. Nothing restarts it unless we do, and buffers scheduled on a
        // stopped engine play nothing: the timeline keeps showing talkers while
        // the speaker stays silent.
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        })
        // A media services reset invalidates every node; rebuild the graph.
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }
            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            wire()
            resume(reason: "media services reset")
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Internal

    var gain: Float = 1.0

    /// Reports every restart attempt (main queue) so a failure is visible in
    /// the UI and log instead of silently losing audio
    var onRestart: ((_ reason: String, _ error: Error?) -> Void)?

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

    /// Restart after anything that stopped the engine behind our back. No-op
    /// when stopped on purpose or already running, so it is safe to call on
    /// every foreground transition. Leaves the category alone: during TX the
    /// session is .playAndRecord and must stay that way.
    func resume(reason: String) {
        guard running, !engine.isRunning else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            player.play()
            onRestart?(reason, nil)
        } catch {
            onRestart?(reason, error)
        }
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

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
    private var running = false
    private var observers: [NSObjectProtocol] = []

    private func wire() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else {
            return
        }
        switch type {
        case .began:
            // iOS has already stopped the engine; nothing to do until it ends
            return
        case .ended:
            // Resume even when iOS doesn't suggest it: a monitor that stays
            // silent after a call is the bug, not an app stealing the session
            resume(reason: "interruption ended")
        @unknown default:
            return
        }
    }
}
