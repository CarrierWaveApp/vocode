import Foundation
import AVFoundation
import CMBELib

// Wraps OP25's software AMBE+2 encoder (GPL v3, vendored in Packages/AMBE)
final class AMBEEncoder {
    private let enc: OpaquePointer

    init?() {
        guard let e = ambe_enc_create() else { return nil }
        enc = e
    }

    deinit { ambe_enc_destroy(enc) }

    // 160 samples of 8 kHz S16 → 96-cell mbelib-layout frame
    func encode(_ pcm: [Int16]) -> [CChar] {
        var cells = [CChar](repeating: 0, count: 96)
        pcm.withUnsafeBufferPointer { p in
            ambe_enc_frame(enc, p.baseAddress, &cells)
        }
        return cells
    }
}

// Speech conditioning for the vocoder: one-pole ~100 Hz high-pass to
// shed rumble, then a slow AGC toward -6 dBFS with a hard limiter.
// AMBE spends its bits on voiced harmonics — it wants hot, clean speech.
struct MicConditioner {
    private var hpPrevIn: Float = 0
    private var hpPrevOut: Float = 0
    private var envelope: Float = 0
    private var gain: Float = 1

    // One-pole high-pass coefficient for 100 Hz at 8 kHz
    private let hpCoeff: Float = 0.9245
    // Modest target: .voiceChat already runs the system AGC ahead of us,
    // and AMBE distorts (and growls low) on hot or clipped input
    private let targetPeak: Float = 0.35
    private let maxGain: Float = 8
    // Below this the input is noise floor: hold gain, don't amplify hiss
    private let silenceFloor: Float = 0.003
    private let envelopeDecay: Float = 0.9995
    private let gainRise: Float = 0.0005
    private let softKnee: Float = 0.6

    mutating func reset() {
        self = MicConditioner()
    }

    mutating func process(_ frame: inout [Int16]) {
        for index in frame.indices {
            let sample = Float(frame[index]) / 32768
            let highPassed = hpCoeff * (hpPrevOut + sample - hpPrevIn)
            hpPrevIn = sample
            hpPrevOut = highPassed

            envelope = max(abs(highPassed), envelope * envelopeDecay)
            let desired: Float
            if envelope < silenceFloor {
                desired = gain
            } else {
                desired = min(maxGain, targetPeak / envelope)
            }
            // Instant attack, slow release: a syllable onset must drop the
            // gain immediately (clipping every word start was audible),
            // while recovery between words stays gradual
            if desired < gain {
                gain = desired
            } else {
                gain += (desired - gain) * gainRise
            }
            var shaped = highPassed * gain
            // Soft knee above the target region instead of a hard clamp
            let magnitude = abs(shaped)
            if magnitude > softKnee {
                let over = magnitude - softKnee
                let squashed = softKnee + over / (1 + over * 4)
                shaped = shaped < 0 ? -squashed : squashed
            }
            frame[index] = Int16(max(-0.98, min(0.98, shaped)) * 32767)
        }
    }
}

// Captures the encoded->decoded copy of a transmission so the operator
// can hear exactly what the network hears
final class TxMonitor {
    private let lock = NSLock()
    private let decoder = AMBEDecoder()
    private var samples: [Float] = []
    private let maxSamples = 8000 * 30

    func reset() {
        lock.lock()
        samples = []
        decoder.reset()
        lock.unlock()
    }

    // Called on the TX queue only (AMBEDecoder isn't thread-safe)
    func append(cells: [CChar]) {
        let decoded = decoder.decode(cells)
        lock.lock()
        if samples.count < maxSamples {
            samples.append(contentsOf: decoded)
        }
        lock.unlock()
    }

    var audio: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

// Encodes mic frames off the main actor and batches three 9-byte on-air
// frames (60 ms) per network packet
final class TxBatcher {
    private let queue = DispatchQueue(label: "dmr.tx")
    private let encoder: AMBEEncoder
    private let send: ([UInt8]) -> Void
    private var frames: [[UInt8]] = []
    var monitor: TxMonitor?

    init(encoder: AMBEEncoder, send: @escaping ([UInt8]) -> Void) {
        self.encoder = encoder
        self.send = send
    }

    func submit(_ pcm: [Int16]) {
        queue.async { [self] in
            let cells = encoder.encode(pcm)
            monitor?.append(cells: cells)
            guard let frame = VoiceBurst.packFrame(cells) else { return }
            frames.append(frame)
            if frames.count >= 3 {
                let payload = frames[0] + frames[1] + frames[2]
                frames.removeFirst(3)
                send(payload)
            }
        }
    }
}

// Microphone → 8 kHz mono Int16, delivered in 160-sample (20 ms) frames
final class MicCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var residue: [Int16] = []
    private var conditioner = MicConditioner()
    private let outFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 8000,
        channels: 1, interleaved: true
    )!

    var onFrame: (([Int16]) -> Void)?

    private var capturing = false
    private var configObserver: NSObjectProtocol?

    init() {
        // A route change (e.g. Bluetooth headset connecting) stops the engine
        // and can change the input hardware format; re-tap at the new format.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.capturing else { return }
            self.stop()
            try? self.start()
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    func start() throws {
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            throw NSError(domain: "MicCapture", code: 1)
        }
        converter = AVAudioConverter(from: hwFormat, to: outFormat)
        residue = []
        conditioner.reset()
        input.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
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

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

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
        guard err == nil, out.frameLength > 0, let ch = out.int16ChannelData?[0] else { return }

        residue.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        while residue.count >= 160 {
            var frame = Array(residue[0..<160])
            residue.removeFirst(160)
            conditioner.process(&frame)
            onFrame?(frame)
        }
    }
}
