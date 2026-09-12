import Foundation

/// G.711 µ-law, the codec AllStar links negotiate. 8 kHz, one byte per
/// sample, so a 20 ms IAX frame is 160 bytes.
enum Ulaw {
    // MARK: Internal

    /// Byte → linear sample, precomputed once
    static let table: [Int16] = (0 ... 255).map { decodeByte(UInt8($0)) }

    static func encode(_ sample: Int16) -> UInt8 {
        var magnitude = Int(sample)
        let sign: UInt8 = magnitude < 0 ? 0x80 : 0
        if magnitude < 0 {
            magnitude = -magnitude
        }
        if magnitude > clip {
            magnitude = clip
        }
        magnitude += bias
        // Exponent is the position of the highest set bit of (magnitude >> 7)
        let top = magnitude >> 7
        let exponent = top > 0 ? min(7, Int.bitWidth - 1 - top.leadingZeroBitCount) : 0
        let mantissa = (magnitude >> (exponent + 3)) & 0x0F
        return ~(sign | UInt8(exponent << 4) | UInt8(mantissa))
    }

    static func decode(_ data: Data) -> [Float] {
        data.map { Float(table[Int($0)]) / 32_768 }
    }

    static func encode(_ pcm: [Int16]) -> Data {
        Data(pcm.map(encode))
    }

    // MARK: Private

    private static let bias = 132
    private static let clip = 32_635

    private static func decodeByte(_ byte: UInt8) -> Int16 {
        let inverted = ~byte
        let exponent = Int((inverted >> 4) & 0x07)
        let mantissa = Int(inverted & 0x0F)
        let magnitude = (((mantissa << 3) + bias) << exponent) - bias
        return Int16(inverted & 0x80 != 0 ? -magnitude : magnitude)
    }
}
