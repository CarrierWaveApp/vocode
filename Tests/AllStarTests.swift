import XCTest
@testable import DMRMonitor

final class UlawTests: XCTestCase {
    // G.711 µ-law is exact on its own codewords: decoding then re-encoding
    // any byte returns that byte. 0x7F is the one exception (negative
    // zero decodes to 0, which re-encodes as positive zero 0xFF).
    func testCodewordRoundTrip() {
        for byte in UInt8(0)...UInt8(255) where byte != 0x7F {
            let sample = Ulaw.table[Int(byte)]
            XCTAssertEqual(Ulaw.encode(sample), byte, "byte \(byte) → \(sample)")
        }
    }

    func testKnownValues() {
        XCTAssertEqual(Ulaw.table[0xFF], 0)          // positive zero
        XCTAssertEqual(Ulaw.table[0x80], 32124)      // most positive
        XCTAssertEqual(Ulaw.table[0x00], -32124)     // most negative
        XCTAssertEqual(Ulaw.encode(0), 0xFF)
    }

    func testEncodeExtremes() {
        XCTAssertEqual(Ulaw.encode(Int16.min + 1), 0x00)
        XCTAssertEqual(Ulaw.encode(Int16.max), 0x80)
    }

    func testBulkHelpers() {
        let pcm: [Int16] = [0, 1000, -1000, 20000, -20000]
        let encoded = Ulaw.encode(pcm)
        XCTAssertEqual(encoded.count, pcm.count)
        let decoded = Ulaw.decode(encoded)
        for (orig, roundTripped) in zip(pcm, decoded) {
            // µ-law is lossy; error is bounded by the segment step size
            XCTAssertEqual(Float(orig) / 32768, roundTripped, accuracy: 0.032)
        }
    }
}

final class ASLDirectoryTests: XCTestCase {
    func testDoHTXTParsing() {
        let json = """
        {"Status":0,"Answer":[{"name":"2000.nodes.allstarlink.org","type":16,"TTL":60,
        "data":"\\"NN=2000\\" \\"IP=18.224.69.177\\" \\"PT=4569\\""}]}
        """
        let parsed = ASLDirectory.parseDoHTXT(Data(json.utf8))
        XCTAssertEqual(parsed?.host, "18.224.69.177")
        XCTAssertEqual(parsed?.port, 4569)
    }

    func testDoHTXTParsingNoAnswer() {
        XCTAssertNil(ASLDirectory.parseDoHTXT(Data("{\"Status\":3}".utf8)))
        XCTAssertNil(ASLDirectory.parseDoHTXT(Data("not json".utf8)))
    }
}
