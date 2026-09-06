import Foundation

enum FrameType: UInt8 {
    case voice = 0
    case voiceSync = 1
    case dataSync = 2
    case unknown = 3
}

enum DataType: UInt8 {
    case voicePIHeader = 0
    case voiceLCHeader = 1
    case terminator = 2
    case csbk = 3
    case other = 15
}

// One DMRD packet from the homebrew protocol
struct DMRDPacket {
    let seq: UInt8
    let src: UInt32
    let dst: UInt32
    let repeaterID: UInt32
    let slot: Int
    let isGroup: Bool
    let frameType: FrameType
    let voiceSeq: UInt8
    let dataType: DataType
    let streamID: UInt32
    let payload: [UInt8]

    static func parse(_ data: Data) -> DMRDPacket? {
        guard data.count >= 53 else { return nil }
        let b = [UInt8](data)
        guard b[0] == 0x44, b[1] == 0x4D, b[2] == 0x52, b[3] == 0x44 else { return nil }

        let flags = b[15]
        let ft = FrameType(rawValue: (flags >> 4) & 0x03) ?? .unknown
        let low = flags & 0x0F

        return DMRDPacket(
            seq: b[4],
            src: be24(b, 5),
            dst: be24(b, 8),
            repeaterID: be32(b, 11),
            slot: (flags & 0x80) != 0 ? 2 : 1,
            isGroup: (flags & 0x40) == 0,
            frameType: ft,
            voiceSeq: ft == .dataSync ? 0 : low,
            dataType: ft == .dataSync ? (DataType(rawValue: low) ?? .other) : .other,
            streamID: be32(b, 16),
            payload: Array(b[20..<53])
        )
    }

    var isVoice: Bool { frameType == .voice || frameType == .voiceSync }

    private static func be24(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 16 | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2])
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }
}

// 33-byte voice burst → three AMBE frames
struct VoiceBurst {
    // Interleave schedule from DSD dmr_const.h
    private static let rW = [
        0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
        0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 2,
        0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2
    ]
    private static let rX = [
        23, 10, 22, 9, 21, 8, 20, 7, 19, 6, 18, 5,
        17, 4, 16, 3, 15, 2, 14, 1, 13, 0, 12, 10,
        11, 9, 10, 8, 9, 7, 8, 6, 7, 5, 6, 4
    ]
    private static let rY = [
        0, 2, 0, 2, 0, 2, 0, 2, 0, 3, 0, 3,
        1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3,
        1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3
    ]
    private static let rZ = [
        5, 3, 4, 2, 3, 1, 2, 0, 1, 13, 0, 12,
        22, 11, 21, 10, 20, 9, 19, 8, 18, 7, 17, 6,
        16, 5, 15, 4, 14, 3, 13, 2, 12, 1, 11, 0
    ]

    let bytes: [UInt8]

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 33 else { return nil }
        self.bytes = Array(bytes[0..<33])
    }

    private func bit(_ i: Int) -> UInt8 {
        (bytes[i >> 3] >> (7 - UInt8(i & 7))) & 1
    }

    private func dibit(_ i: Int) -> UInt8 {
        bit(2 * i) << 1 | bit(2 * i + 1)
    }

    private func place(_ f: inout [CChar], _ i: Int, _ d: UInt8) {
        f[Self.rW[i] * 24 + Self.rX[i]] = CChar((d >> 1) & 1)
        f[Self.rY[i] * 24 + Self.rZ[i]] = CChar(d & 1)
    }

    // One standalone 9-byte on-air AMBE frame (as delivered by the Open
    // Terminal Protocol) → the same [4][24] mbelib cell layout.
    static func ambeFrame(_ b: [UInt8]) -> [CChar]? {
        guard b.count == 9 else { return nil }
        func bit(_ i: Int) -> UInt8 {
            (b[i >> 3] >> (7 - UInt8(i & 7))) & 1
        }
        var f = [CChar](repeating: 0, count: 96)
        for i in 0..<36 {
            let d = bit(2 * i) << 1 | bit(2 * i + 1)
            f[rW[i] * 24 + rX[i]] = CChar((d >> 1) & 1)
            f[rY[i] * 24 + rZ[i]] = CChar(d & 1)
        }
        return f
    }

    // Each frame is [4][24] flattened
    func ambeFrames() -> [[CChar]] {
        var f1 = [CChar](repeating: 0, count: 96)
        var f2 = [CChar](repeating: 0, count: 96)
        var f3 = [CChar](repeating: 0, count: 96)

        for i in 0..<36 { place(&f1, i, dibit(i)) }
        for i in 0..<18 { place(&f2, i, dibit(36 + i)) }
        // Dibits 54..77 are sync or embedded signalling
        for i in 18..<36 { place(&f2, i, dibit(60 + i)) }
        for i in 0..<36 { place(&f3, i, dibit(96 + i)) }

        return [f1, f2, f3]
    }
}
