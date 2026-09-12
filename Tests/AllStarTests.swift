import XCTest
@testable import DMRMonitor

// MARK: - UlawTests

final class UlawTests: XCTestCase {
    /// G.711 µ-law is exact on its own codewords: decoding then re-encoding
    /// any byte returns that byte. 0x7F is the one exception (negative
    /// zero decodes to 0, which re-encodes as positive zero 0xFF).
    func testCodewordRoundTrip() {
        for byte in UInt8(0) ... UInt8(255) where byte != 0x7F {
            let sample = Ulaw.table[Int(byte)]
            XCTAssertEqual(Ulaw.encode(sample), byte, "byte \(byte) → \(sample)")
        }
    }

    func testKnownValues() {
        XCTAssertEqual(Ulaw.table[0xFF], 0) // positive zero
        XCTAssertEqual(Ulaw.table[0x80], 32_124) // most positive
        XCTAssertEqual(Ulaw.table[0x00], -32_124) // most negative
        XCTAssertEqual(Ulaw.encode(0), 0xFF)
    }

    func testEncodeExtremes() {
        XCTAssertEqual(Ulaw.encode(Int16.min + 1), 0x00)
        XCTAssertEqual(Ulaw.encode(Int16.max), 0x80)
    }

    func testBulkHelpers() {
        let pcm: [Int16] = [0, 1_000, -1_000, 20_000, -20_000]
        let encoded = Ulaw.encode(pcm)
        XCTAssertEqual(encoded.count, pcm.count)
        let decoded = Ulaw.decode(encoded)
        for (orig, roundTripped) in zip(pcm, decoded) {
            // µ-law is lossy; error is bounded by the segment step size
            XCTAssertEqual(Float(orig) / 32_768, roundTripped, accuracy: 0.032)
        }
    }
}
