import Foundation
import SwiftUI

// MARK: - ListenState

enum ListenState: String, Codable {
    case live
    case muted
    case off
}

// MARK: - Talkgroup

struct Talkgroup: Codable, Identifiable, Equatable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), tg: UInt32, name: String = "", listen: ListenState = .live) {
        self.id = id
        self.tg = tg
        self.name = name
        self.listen = listen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tg = try container.decode(UInt32.self, forKey: .tg)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        listen = try container.decodeIfPresent(ListenState.self, forKey: .listen) ?? .live
    }

    // MARK: Internal

    var id: UUID
    var tg: UInt32
    var name: String
    var listen: ListenState
}

// MARK: - Settings

/// Persisted in UserDefaults via @AppStorage
final class Settings: ObservableObject {
    // MARK: Lifecycle

    init() {
        // Migrate the old free-text options field once; in single-talkgroup
        // mode only the first entry starts live
        if talkgroupsJSON.isEmpty {
            let names: [UInt32: String] = [91: "Worldwide", 3_100: "USA Nationwide"]
            talkgroupList = legacyTalkgroups.enumerated().map { i, tg in
                Talkgroup(tg: tg, name: names[tg] ?? "",
                          listen: (singleTG && i > 0) ? .off : .live)
            }
        }
        // After the talkgroup migration: the DMR destination it builds
        // captures the migrated list
        migrateDestinationsIfNeeded()
    }

    // MARK: Internal

    @AppStorage("netMode") var netMode = "openterminal"
    @AppStorage("host") var host = "3103.master.brandmeister.network"
    @AppStorage("port") var port = 62_031
    @AppStorage("otpPort") var otpPort = 54_006
    @AppStorage("dmrID") var dmrID = ""
    @AppStorage("suffix") var suffix = "01"
    @AppStorage("password") var password = ""
    @AppStorage("callsign") var callsign = ""
    @AppStorage("options") var options = "TS2_1=91;TS2_2=3100"
    @AppStorage("location") var location = ""
    @AppStorage("talkgroupsJSON") var talkgroupsJSON = ""
    @AppStorage("dstarHost") var dstarHost = ""
    @AppStorage("dstarModule") var dstarModule = "B"
    // AllStar: our registered node credentials plus the node to link to
    @AppStorage("aslMyNode") var aslMyNode = ""
    @AppStorage("aslPassword") var aslPassword = ""
    @AppStorage("aslTarget") var aslTarget = ""
    // Open Terminal only: probe all masters at connect and use the fastest.
    // "Master" is BrandMeister's own term for its servers.
    // swiftlint:disable:next inclusive_language
    @AppStorage("autoMaster") var autoMaster = true
    @AppStorage("txTargetTG") var txTargetTG = 0
    // Default: exactly one talkgroup subscribed at a time; going live on
    // one switches the others off. Turn off for multi-talkgroup monitoring.
    @AppStorage("singleTG") var singleTG = true
    // Push-to-talk style: false = hold to talk, true = tap to key up and
    // tap again to stop
    @AppStorage("pttToggle") var pttToggle = false
    // TX time-out timer in seconds; 0 disables it
    @AppStorage("txTimeoutSecs") var txTimeoutSecs = 120
    // QRZ XML API credentials for map geocoding; plain AppStorage matches
    // the existing hotspot-password precedent
    @AppStorage("qrzUser") var qrzUser = ""
    @AppStorage("qrzPassword") var qrzPassword = ""
    @AppStorage("mapOverlay") var mapOverlay = true
    // 0 = follow my subscribed talkgroups
    @AppStorage("mapOverlayTG") var mapOverlayTG = 0
    // Buddy watch: server-side push when watched callsigns key up
    @AppStorage("buddyWatchEnabled") var buddyWatchEnabled = false
    @AppStorage("buddyServerURL") var buddyServerURL = "https://dmr.carrierwave.app"
    @AppStorage("buddyAPIToken") var buddyAPIToken = ""
    @AppStorage("buddyDeviceID") var buddyDeviceID = ""
    @AppStorage("buddyLastToken") var buddyLastToken = ""
    @AppStorage("buddyLastSynced") var buddyLastSynced = ""
    @AppStorage("buddiesJSON") var buddiesJSON = ""
    @AppStorage("netsJSON") var netsJSON = ""
    // Saved destinations (see Destination.swift); the keys above stay the
    // working state the connect path reads
    @AppStorage("destinationsJSON") var destinationsJSON = ""
    @AppStorage("activeDestinationID") var activeDestinationID = ""

    var talkgroupList: [Talkgroup] {
        get {
            guard let data = talkgroupsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Talkgroup].self, from: data)
            else {
                return []
            }
            return list
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }
            talkgroupsJSON = String(bytes: data, encoding: .utf8) ?? ""
        }
    }

    var txTarget: Talkgroup? {
        guard txTargetTG > 0 else {
            return nil
        }
        return talkgroupList.first { $0.tg == UInt32(txTargetTG) }
    }

    var buddyConfigured: Bool {
        !buddyServerURL.trimmingCharacters(in: .whitespaces).isEmpty && !buddyAPIToken.isEmpty
    }

    var buddyList: [Buddy] {
        get {
            guard let data = buddiesJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Buddy].self, from: data)
            else {
                return []
            }
            return list
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(bytes: data, encoding: .utf8)
            else {
                return
            }
            buddiesJSON = json
        }
    }

    var netList: [Net] {
        get {
            guard let data = netsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Net].self, from: data)
            else {
                return []
            }
            return list
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(bytes: data, encoding: .utf8)
            else {
                return
            }
            netsJSON = json
        }
    }

    var qrzConfigured: Bool {
        !qrzUser.trimmingCharacters(in: .whitespaces).isEmpty && !qrzPassword.isEmpty
    }

    /// Talkgroups the map's BrandMeister overlay follows
    var mapOverlayTalkgroups: Set<UInt32> {
        mapOverlayTG > 0 ? [UInt32(mapOverlayTG)] : Set(activeTalkgroups)
    }

    /// Subscribed on the network (live + muted)
    var activeTalkgroups: [UInt32] {
        talkgroupList.filter { $0.tg > 0 && $0.listen != .off }.map(\.tg)
    }

    /// Locally silenced (muted + off; off is belt-and-braces for homebrew,
    /// where mid-session unsubscribe isn't possible)
    var silencedTalkgroups: Set<UInt32> {
        Set(talkgroupList.filter { $0.tg > 0 && $0.listen != .live }.map(\.tg))
    }

    var repeaterID: UInt32? {
        UInt32(dmrID.trimmingCharacters(in: .whitespaces) + suffix.trimmingCharacters(in: .whitespaces))
    }

    var talkgroups: [UInt32] {
        talkgroupList.map(\.tg).filter { $0 > 0 }
    }

    /// MMDVMHost-style options string for the homebrew RPTO packet;
    /// off talkgroups are left out entirely
    var homebrewOptions: String {
        activeTalkgroups.enumerated()
            .map { "TS2_\($0.offset + 1)=\($0.element)" }
            .joined(separator: ";")
    }

    var rewindConfig: RewindConfig? {
        guard let id = UInt32(dmrID.trimmingCharacters(in: .whitespaces)),
              !host.isEmpty, !password.isEmpty,
              otpPort > 0, otpPort < 65_536
        else {
            return nil
        }
        return RewindConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: UInt16(otpPort),
            dmrID: id,
            password: password,
            talkgroups: activeTalkgroups
        )
    }

    var dextraConfig: DExtraConfig? {
        let call = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let host = dstarHost.trimmingCharacters(in: .whitespaces)
        let mod = dstarModule.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty, !host.isEmpty, let module = mod.first else {
            return nil
        }
        return DExtraConfig(host: host, callsign: call, module: module)
    }

    /// Partial config for AllStar; host/port get resolved at connect time
    var allstarConfig: IAXConfig? {
        let myNode = aslMyNode.trimmingCharacters(in: .whitespaces)
        let target = aslTarget.trimmingCharacters(in: .whitespaces)
        guard !myNode.isEmpty, !aslPassword.isEmpty, !target.isEmpty else {
            return nil
        }
        return IAXConfig(
            myNode: myNode, password: aslPassword, targetNode: target,
            host: "", port: 4_569,
            callsign: callsign.trimmingCharacters(in: .whitespaces).uppercased()
        )
    }

    /// Human-readable label for the connected server/reflector
    var connectedSummary: String {
        if netMode == "allstar" {
            return "Node \(aslTarget.trimmingCharacters(in: .whitespaces))"
        }
        if netMode == "dstar" {
            let host = dstarHost.trimmingCharacters(in: .whitespaces)
            let name = XLXDirectory.reflector(forHost: host)?.name
                ?? host.split(separator: ".").first.map(String.init)?.uppercased()
                ?? host
            return "\(name) \(dstarModule.uppercased())"
        }
        if let server = BMDirectory.master(forHost: host) {
            return "\(server.id) \(server.country)"
        }
        return host
    }

    var homebrewConfig: HomebrewConfig? {
        guard let id = repeaterID,
              !host.isEmpty, !password.isEmpty, !callsign.isEmpty,
              port > 0, port < 65_536
        else {
            return nil
        }
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

    func tgName(_ tg: UInt32) -> String? {
        let name = talkgroupList.first { $0.tg == tg }?.name
        return (name?.isEmpty ?? true) ? nil : name
    }

    // MARK: - Listen states and TX target

    func listenState(_ tg: UInt32) -> ListenState? {
        talkgroupList.first { $0.tg == tg }?.listen
    }

    func setListen(_ tg: UInt32, _ state: ListenState) {
        var list = talkgroupList
        guard let i = list.firstIndex(where: { $0.tg == tg }) else {
            return
        }
        list[i].listen = state
        if singleTG, state == .live {
            for j in list.indices where j != i && list[j].listen != .off {
                list[j].listen = .off
            }
            txTargetTG = Int(tg)
        }
        talkgroupList = list
    }

    /// Collapse to one subscribed talkgroup: the TX target if it's live,
    /// else the first live one. No-op when nothing is live.
    func enforceSingleLive() {
        var list = talkgroupList
        let keep = list.firstIndex { $0.tg == UInt32(txTargetTG) && $0.listen == .live }
            ?? list.firstIndex { $0.listen == .live }
        guard let keep else {
            return
        }
        var changed = false
        for i in list.indices where i != keep && list[i].listen != .off {
            list[i].listen = .off
            changed = true
        }
        if changed {
            talkgroupList = list
        }
        txTargetTG = Int(list[keep].tg)
    }

    // MARK: Private

    /// Accepts both MMDVMHost options ("TS2_1=91;TS2_2=3100") and a bare
    /// list ("91;3100" or "91,3100"); used only for one-time migration.
    private var legacyTalkgroups: [UInt32] {
        options.split(whereSeparator: { ";,".contains($0) }).compactMap { part in
            let value = part.split(separator: "=").last ?? part
            return UInt32(value.trimmingCharacters(in: .whitespaces))
        }
    }
}
