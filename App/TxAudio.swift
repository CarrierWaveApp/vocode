import AVFoundation
import CMBELib
import Foundation

// MARK: - AMBEEncoder

/// Wraps OP25's software AMBE+2 encoder (GPL v3, vendored in Packages/AMBE)
final class AMBEEncoder {
    // MARK: Lifecycle

    /// `trimDb` is the operator's TX level setting on top of the fixed
    /// calibration; positive is louder on the air
    init?(trimDb: Int = 0) {
        guard let e = ambe_enc_create() else {
            return nil
        }
        enc = e
        ambe_enc_set_gain_adjust(e, Self.levelCalibration - Float(trimDb) / 6.02)
    }

    deinit { ambe_enc_destroy(enc) }

    // MARK: Internal

    /// Subtracted from the encoded gain parameter (log2 units, 1.0 = 6 dB).
    /// OP25's encoder runs ~13.5 dB hot against mbelib, the scale this app
    /// plays real radios at, so uncorrected TX clipped on every receiver
    /// above about -14 dBFS of mic input. Measured in AMBETests/LevelTests.
    static let levelCalibration: Float = 2.25

    /// 160 samples of 8 kHz S16 → 96-cell mbelib-layout frame
    func encode(_ pcm: [Int16]) -> [CChar] {
        var cells = [CChar](repeating: 0, count: 96)
        pcm.withUnsafeBufferPointer { pcmPointer in
            ambe_enc_frame(enc, pcmPointer.baseAddress, &cells)
        }
        return cells
    }

    // MARK: Private

    private let enc: OpaquePointer
}

// MARK: - TXBurst

/// One of our own transmissions, for the activity timeline
struct TXBurst: Identifiable, Equatable {
    let id = UUID()
    let dst: UInt32
    let started: Date
    var ended: Date?
    // AllStar: the linked node label, shown where DMR shows the talkgroup
    var channel: String?
}

// MARK: - MicConditioner

/// Speech conditioning for the vocoder: high-pass, then a frame-rate peak
/// limiter that holds the level AMBE likes. No makeup gain and no
/// waveshaping in the normal path.
///
/// History: a sample-rate AGC modulated gain at audio rate (distortion), and
/// the fixed 2x gain + soft knee that replaced it drove the system AGC's
/// already-hot output into the knee on every voiced peak, which other
/// stations heard as "modulated and overdriven". AMBE growls on hot input;
/// it wants clean speech around -6 dBFS. The limiter here computes one gain
/// per 20 ms frame (instant attack, slow release) and ramps between frames,
/// so the gain never changes at audio rate.
struct MicConditioner {
    // MARK: Internal

    mutating func reset() {
        self = MicConditioner()
    }

    mutating func process(_ frame: inout [Int16]) {
        var filtered = [Float](repeating: 0, count: frame.count)
        var peak: Float = 0
        for index in frame.indices {
            let sample = Float(frame[index]) / 32_768
            let highPassed = hpCoeff * (hpPrevOut + sample - hpPrevIn)
            hpPrevIn = sample
            hpPrevOut = highPassed
            filtered[index] = highPassed
            peak = max(peak, abs(highPassed))
        }

        // Instant attack: this frame already lands at the ceiling. Slow
        // release: creep back toward unity between words, not within them.
        let needed = peak > ceiling ? ceiling / peak : 1
        let target: Float = needed < gain ? needed : min(needed, gain + (needed - gain) * releasePerFrame)
        let previous = gain
        gain = target

        let ramp = min(rampSamples, frame.count)
        for index in frame.indices {
            let fraction = index < ramp ? Float(index + 1) / Float(ramp) : 1
            let frameGain = previous + (target - previous) * fraction
            let shaped = filtered[index] * frameGain
            // Safety only: with 6 dB between ceiling and clamp this engages
            // just for a loud onset caught mid-ramp
            frame[index] = Int16(max(-clamp, min(clamp, shaped)) * 32_767)
        }
    }

    // MARK: Private

    private var hpPrevIn: Float = 0
    private var hpPrevOut: Float = 0
    private var gain: Float = 1

    /// ~100 Hz one-pole high-pass at 8 kHz
    private let hpCoeff: Float = 0.9245
    /// -6 dBFS peak into the encoder
    private let ceiling: Float = 0.5
    /// Fraction of the way back toward the needed gain per 20 ms frame:
    /// most of the recovery inside ~150 ms
    private let releasePerFrame: Float = 0.15
    // 4 ms gain ramp at the start of each frame
    private let rampSamples = 32
    private let clamp: Float = 0.95
}

// MARK: - TxMonitor

/// Captures the encoded->decoded copy of a transmission so the operator
/// can hear exactly what the network hears
final class TxMonitor {
    // MARK: Internal

    var audio: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    var micAudio: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return micSamples
    }

    func reset() {
        lock.lock()
        samples = []
        micSamples = []
        decoder.reset()
        lock.unlock()
    }

    /// Called on the TX queue only (AMBEDecoder isn't thread-safe)
    func append(cells: [CChar]) {
        let decoded = decoder.decode(cells)
        lock.lock()
        if samples.count < maxSamples {
            samples.append(contentsOf: decoded)
        }
        lock.unlock()
    }

    /// The conditioned PCM going INTO the encoder — pre-codec reference
    /// for bisecting capture problems from codec problems
    func appendMic(_ frame: [Int16]) {
        lock.lock()
        if micSamples.count < maxSamples {
            micSamples.append(contentsOf: frame.map { Float($0) / 32_768 })
        }
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private let decoder = AMBEDecoder()
    private var samples: [Float] = []
    private var micSamples: [Float] = []
    private let maxSamples = 8_000 * 30
}

// MARK: - TxBatcher

/// Encodes mic frames off the main actor and batches three 9-byte on-air
/// frames (60 ms) per network packet
final class TxBatcher {
    // MARK: Lifecycle

    init(encoder: AMBEEncoder, send: @escaping ([UInt8]) -> Void) {
        self.encoder = encoder
        self.send = send
    }

    // MARK: Internal

    var monitor: TxMonitor?

    func submit(_ pcm: [Int16]) {
        queue.async { [self] in
            let cells = encoder.encode(pcm)
            monitor?.append(cells: cells)
            guard let frame = VoiceBurst.packFrame(cells) else {
                return
            }
            frames.append(frame)
            if frames.count >= 3 {
                let payload = frames[0] + frames[1] + frames[2]
                frames.removeFirst(3)
                send(payload)
            }
        }
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "dmr.tx")
    private let encoder: AMBEEncoder
    private let send: ([UInt8]) -> Void
    private var frames: [[UInt8]] = []
}

// MARK: - MicCapture

/// Microphone → 8 kHz mono Int16, delivered in 160-sample (20 ms) frames
final class MicCapture {
    // MARK: Lifecycle

    init() {
        // A route change (e.g. Bluetooth headset connecting) stops the engine
        // and can change the input hardware format; re-tap at the new format.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, capturing else {
                return
            }
            stop()
            try? start()
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    // MARK: Internal

    var onFrame: (([Int16]) -> Void)?
    // Diagnostic: reports the live input format at (re)start
    var onFormat: ((String) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            throw NSError(domain: "MicCapture", code: 1)
        }
        converter = AVAudioConverter(from: hwFormat, to: outFormat)
        residue = []
        conditioner.reset()
        onFormat?("\(Int(hwFormat.sampleRate)) Hz, \(hwFormat.channelCount) ch → 8000 Hz")
        input.installTap(onBus: 0, bufferSize: 1_024, format: hwFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        capturing = true
    }

    func stop() {
        capturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        residue = []
    }

    // MARK: Private

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var residue: [Int16] = []
    private var conditioner = MicConditioner()
    private let outFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 8_000,
        channels: 1, interleaved: true
    )!

    private var capturing = false
    private var configObserver: NSObjectProtocol?

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converter else {
            return
        }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            return
        }

        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, out.frameLength > 0, let ch = out.int16ChannelData?[0] else {
            return
        }

        residue.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        while residue.count >= 160 {
            var frame = Array(residue[0 ..< 160])
            residue.removeFirst(160)
            conditioner.process(&frame)
            onFrame?(frame)
        }
    }
}
