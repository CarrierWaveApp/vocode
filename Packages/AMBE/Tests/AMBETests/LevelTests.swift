import CMBELib
import XCTest

/// Level calibration for the OP25 encoder against mbelib's decoder, which is
/// the scale the app plays received radios at. Uncorrected, the round trip
/// comes out ~13.5 dB hot and clips above about -14 dBFS in; other stations
/// heard that as "super overmodulated". 2.25 (log2 units) brings it to
/// within ~1.5 dB from -40 to -6 dBFS.
final class LevelTests: XCTestCase {
    // MARK: Internal

    static let calibration: Float = 2.25

    func testCalibratedRoundtripIsUnityAndDoesNotClip() {
        for amplitude in [1_000.0, 2_000.0, 8_000.0, 16_000.0] {
            let (ratioDb, peak) = roundtrip(amplitude: amplitude, adjust: Self.calibration)
            XCTAssertLessThan(abs(ratioDb), 3, "round trip at \(Int(amplitude)) is \(ratioDb) dB")
            XCTAssertLessThan(peak, 32_000, "decoded output clips at \(Int(amplitude)) in")
        }
    }

    func testUncalibratedEncoderIsHot() {
        // Guards the premise: if upstream ever fixes this, drop the calibration
        let (ratioDb, _) = roundtrip(amplitude: 2_000, adjust: 0)
        XCTAssertGreaterThan(ratioDb, 10)
    }

    // MARK: Private

    private func roundtrip(amplitude: Double, adjust: Float) -> (Float, Int16) {
        guard let enc = ambe_enc_create() else {
            XCTFail("encoder create failed")
            return (0, 0)
        }
        defer { ambe_enc_destroy(enc) }
        ambe_enc_set_gain_adjust(enc, adjust)
        var ctx = ambe_ctx()
        ambe_ctx_init(&ctx)
        var inEnergy = 0.0
        var outEnergy = 0.0
        var peak: Int16 = 0
        for frame in 0 ..< 50 {
            var pcm = [Int16](repeating: 0, count: 160)
            for i in 0 ..< 160 {
                let time = Double(frame * 160 + i) / 8_000.0
                // Two harmonics: more voice-like than a sine for the pitch tracker
                pcm[i] = Int16(amplitude * (0.6 * sin(2 * .pi * 150 * time) + 0.4 * sin(2 * .pi * 450 * time)))
            }
            var cells = [CChar](repeating: 0, count: 96)
            ambe_enc_frame(enc, &pcm, &cells)
            var out = [Int16](repeating: 0, count: 160)
            _ = ambe_decode_frame(&ctx, &cells, &out, 3)
            guard frame >= 10 else {
                continue
            }
            for i in 0 ..< 160 {
                inEnergy += Double(pcm[i]) * Double(pcm[i])
                outEnergy += Double(out[i]) * Double(out[i])
                peak = max(peak, abs(out[i]))
            }
        }
        return (Float(10 * log10(outEnergy / inEnergy)), peak)
    }
}
