import Foundation
import SwiftUI

// Persisted in UserDefaults via @AppStorage
final class Settings: ObservableObject {
    @AppStorage("netMode") var netMode = "openterminal"
    @AppStorage("host") var host = "3103.master.brandmeister.network"
    @AppStorage("port") var port = 62031
    @AppStorage("otpPort") var otpPort = 54006
    @AppStorage("dmrID") var dmrID = ""
    @AppStorage("suffix") var suffix = "01"
    @AppStorage("password") var password = ""
    @AppStorage("callsign") var callsign = ""
    @AppStorage("options") var options = "TS2_1=91;TS2_2=3100"
    @AppStorage("location") var location = ""

    var repeaterID: UInt32? {
        UInt32(dmrID.trimmingCharacters(in: .whitespaces) + suffix.trimmingCharacters(in: .whitespaces))
    }

    // Accepts both MMDVMHost options ("TS2_1=91;TS2_2=3100") and a bare
    // list ("91;3100" or "91,3100").
    var talkgroups: [UInt32] {
        options.split(whereSeparator: { ";,".contains($0) }).compactMap { part in
            let value = part.split(separator: "=").last ?? part
            return UInt32(value.trimmingCharacters(in: .whitespaces))
        }
    }

    var rewindConfig: RewindConfig? {
        guard let id = UInt32(dmrID.trimmingCharacters(in: .whitespaces)),
              !host.isEmpty, !password.isEmpty,
              otpPort > 0, otpPort < 65536 else { return nil }
        return RewindConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: UInt16(otpPort),
            dmrID: id,
            password: password,
            talkgroups: talkgroups
        )
    }

    var homebrewConfig: HomebrewConfig? {
        guard let id = repeaterID,
              !host.isEmpty, !password.isEmpty, !callsign.isEmpty,
              port > 0, port < 65536 else { return nil }
        return HomebrewConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: UInt16(port),
            repeaterID: id,
            password: password,
            callsign: callsign.uppercased(),
            options: options.trimmingCharacters(in: .whitespaces),
            location: location
        )
    }
}
