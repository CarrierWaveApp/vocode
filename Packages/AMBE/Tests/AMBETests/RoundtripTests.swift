import CMBELib
import XCTest

/// Encoder output must decode cleanly through the same mbelib path the app
/// uses for received frames: zero FEC errors and recognizable audio energy.
final class RoundtripTests: XCTestCase {
    func testEncodeDecodeRoundtrip() {
        guard let enc = ambe_enc_create() else {
            XCTFail("encoder create failed")
            return
        }
        defer { ambe_enc_destroy(enc) }

        var ctx = ambe_ctx()
        ambe_ctx_init(&ctx)

        var totalErrors: Int32 = 0
        var energy: Double = 0
        let frames = 50

        for frameIndex in 0 ..< frames {
            // 440 Hz tone at moderate level
            var pcm = [Int16](repeating: 0, count: 160)
            for i in 0 ..< 160 {
                let time = Double(frameIndex * 160 + i) / 8_000.0
                pcm[i] = Int16(8_000.0 * sin(2.0 * .pi * 440.0 * time))
            }
            var cells = [CChar](repeating: 0, count: 96)
            ambe_enc_frame(enc, &pcm, &cells)

            var out = [Int16](repeating: 0, count: 160)
            let errs = ambe_decode_frame(&ctx, &cells, &out, 3)
            totalErrors += errs
            for sample in out {
                energy += Double(sample) * Double(sample)
            }
        }

        XCTAssertEqual(totalErrors, 0, "FEC errors mean the cell packing does not match mbelib")
        let rms = (energy / Double(frames * 160)).squareRoot()
        XCTAssertGreaterThan(rms, 100, "decoded audio is near-silent; codec roundtrip failed")
    }
}
