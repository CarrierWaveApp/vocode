import Foundation

/// Maps the 9 AMBE bytes of a D-STAR network voice frame into mbelib's
/// ambe_fr[4][24] cell layout for mbe_processAmbe3600x2400Frame.
///
/// Bit order: MMDVM demodulates D-STAR with LSB-first byte packing
/// (DStarRX.cpp WRITE_BIT2) and gateways pass those bytes through
/// unchanged, so transmission-order bit i lives at byte[i/8] bit (i%8).
/// The placement tables (dW/dX upstream) come from DSD's dstar_const.h (ISC license,
/// same provenance as the DMR tables in DMRFrame.swift).
enum DStarFrame {
    // MARK: Internal

    /// 9 network bytes → 96 cells ([4][24] flattened) for the decode shim
    static func cells(from ambe: [UInt8]) -> [CChar] {
        var cells = [CChar](repeating: 0, count: 96)
        guard ambe.count >= 9 else {
            return cells
        }
        for bit in 0 ..< 72 {
            let value = (ambe[bit / 8] >> (bit % 8)) & 1
            cells[rowTable[bit] * 24 + colTable[bit]] = CChar(value)
        }
        return cells
    }

    // MARK: Private

    private static let rowTable: [Int] = [
        0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
        3, 2, 1, 1, 3, 2, 1, 1, 0, 0, 3, 2,
        0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
        3, 2, 1, 1, 3, 2, 1, 1, 0, 0, 3, 2,
        0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
        3, 2, 1, 1, 3, 3, 2, 1, 0, 0, 3, 3,
    ]

    private static let colTable: [Int] = [
        10, 22, 11, 9, 10, 22, 11, 23, 8, 20, 9, 21,
        10, 8, 9, 21, 8, 6, 7, 19, 8, 20, 9, 7,
        6, 18, 7, 5, 6, 18, 7, 19, 4, 16, 5, 17,
        6, 4, 5, 17, 4, 2, 3, 15, 4, 16, 5, 3,
        2, 14, 3, 1, 2, 14, 3, 15, 0, 12, 1, 13,
        2, 0, 1, 13, 0, 12, 10, 11, 0, 12, 1, 13,
    ]
}
