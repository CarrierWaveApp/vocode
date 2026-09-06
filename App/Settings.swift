import Foundation
import SwiftUI

struct Talkgroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var tg: UInt32
    var name: String
}

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
    @AppStorage("talkgroupsJSON") var talkgroupsJSON = ""

    init() {
        // Migrate the old free-text options field once
        if talkgroupsJSON.isEmpty {
            let names: [UInt32: String] = [91: "Worldwide", 3100: "USA Nationwide"]
            talkgroupList = legacyTalkgroups.map { Talkgroup(tg: $0, name: names[$0] ?? "") }
        }
    }

    var talkgroupList: [Talkgroup] {
        get {
            guard let data = talkgroupsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Talkgroup].self, from: data)
            else { return [] }
            return list
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            talkgroupsJSON = String(decoding: data, as: UTF8.self)
        }
    }

    func tgName(_ tg: UInt32) -> String? {
        let name = talkgroupList.first { $0.tg == tg }?.name
        return (name?.isEmpty ?? true) ? nil : name
    }

    var repeaterID: UInt32? {
        UInt32(dmrID.trimmingCharacters(in: .whitespaces) + suffix.trimmingCharacters(in: .whitespaces))
    }

    var talkgroups: [UInt32] {
        talkgroupList.map(\.tg).filter { $0 > 0 }
    }

    // Accepts both MMDVMHost options ("TS2_1=91;TS2_2=3100") and a bare
    // list ("91;3100" or "91,3100"); used only for one-time migration.
    private var legacyTalkgroups: [UInt32] {
        options.split(whereSeparator: { ";,".contains($0) }).compactMap { part in
            let value = part.split(separator: "=").last ?? part
            return UInt32(value.trimmingCharacters(in: .whitespaces))
        }
    }

    // MMDVMHost-style options string for the homebrew RPTO packet
    var homebrewOptions: String {
        talkgroups.enumerated()
            .map { "TS2_\($0.offset + 1)=\($0.element)" }
            .joined(separator: ";")
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
            options: homebrewOptions,
            location: location
        )
    }
}
