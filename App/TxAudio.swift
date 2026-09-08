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

// Encodes mic frames off the main actor and batches three 9-byte on-air
// frames (60 ms) per network packet
final class TxBatcher {
    private let queue = DispatchQueue(label: "dmr.tx")
    private let encoder: AMBEEncoder
    private let send: ([UInt8]) -> Void
    private var frames: [[UInt8]] = []

    init(encoder: AMBEEncoder, send: @escaping ([UInt8]) -> Void) {
        self.encoder = encoder
        self.send = send
    }

    func submit(_ pcm: [Int16]) {
        queue.async { [self] in
            let cells = encoder.encode(pcm)
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
            let frame = Array(residue[0..<160])
            residue.removeFirst(160)
            onFrame?(frame)
        }
    }
}
