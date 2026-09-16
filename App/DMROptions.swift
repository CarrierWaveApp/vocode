import Foundation

// MARK: - DMROptionsDialect

/// How a network wants static talkgroups written in the `RPTO` options
/// string. The wire format of `RPTO` is just an opaque byte string, so each
/// network family parses its payload its own way and silently ignores a
/// string it does not recognise — which is why the wrong dialect looks like
/// a healthy, completely silent link rather than an error.
///
/// Three forms are in circulation:
///
/// - `.freeDMR` — `TS2=91,3100;` Comma-separated per slot. FreeDMR and the
///   HBLink systems built on it, AmComm included.
/// - `.indexed` — `TS2_1=91;TS2_2=3100;` One key per talkgroup. DMR+/IPSC2,
///   and the form MMDVMHost writes for BrandMeister.
/// - `.none` — send no options at all.
///
/// Both documented dialects require the **trailing semicolon**; DMR+'s own
/// documentation calls it out as the thing people most often get wrong.
enum DMROptionsDialect: String {
    case freeDMR
    case indexed
    case none

    // MARK: Internal

    /// Picks the dialect from the network's name in `DMR_Hosts.txt`.
    ///
    /// AmComm was confirmed FreeDMR from its own dashboard, which carries the
    /// FreeDMR logo and the K0USY/HBlink credit. ADN and FreeSTAR are listed
    /// as FreeDMR-family in the same file. An unrecognised network — and any
    /// hand-typed host — falls back to `.indexed`, the broader of the two.
    ///
    /// TGIF is deliberately `.none`: its statics are managed from the
    /// tgif.network dashboard, and this has not been verified on air.
    static func forNetwork(_ network: String) -> DMROptionsDialect {
        let name = network.lowercased()
        if name.contains("tgif") {
            return .none
        }
        if name.contains("freedmr") || name.contains("hblink")
            || name.contains("amcomm") || name.contains("freestar")
            || name.contains("adn")
        {
            return .freeDMR
        }
        return .indexed
    }

    /// Renders `talkgroups` as an options string. Everything goes on
    /// timeslot 2: the app presents as a simplex hotspot, which has no TS1.
    func options(talkgroups: [UInt32]) -> String {
        guard !talkgroups.isEmpty else {
            return ""
        }
        switch self {
        case .freeDMR:
            return "TS2=" + talkgroups.map(String.init).joined(separator: ",") + ";"
        case .indexed:
            return talkgroups
                .enumerated()
                .map { "TS2_\($0.offset + 1)=\($0.element);" }
                .joined()
        case .none:
            return ""
        }
    }
}
