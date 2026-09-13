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

    /// Backing defaults for every @AppStorage key. Tests MUST point this
    /// at their own suite before constructing a Settings — on-device test
    /// runs share the real app container, and a test that touches
    /// UserDefaults.standard wipes the user's actual configuration.
    static var store: UserDefaults = .standard

    @AppStorage("netMode", store: Settings.store) var netMode = "openterminal"
    @AppStorage("host", store: Settings.store) var host = "3103.master.brandmeister.network"
    @AppStorage("port", store: Settings.store) var port = 62_031
    @AppStorage("otpPort", store: Settings.store) var otpPort = 54_006
    @AppStorage("dmrID", store: Settings.store) var dmrID = ""
    @AppStorage("suffix", store: Settings.store) var suffix = "01"
    @AppStorage("password", store: Settings.store) var password = ""
    @AppStorage("callsign", store: Settings.store) var callsign = ""
    @AppStorage("options", store: Settings.store) var options = "TS2_1=91;TS2_2=3100"
    @AppStorage("location", store: Settings.store) var location = ""
    @AppStorage("talkgroupsJSON", store: Settings.store) var talkgroupsJSON = ""
    @AppStorage("dstarHost", store: Settings.store) var dstarHost = ""
    @AppStorage("dstarModule", store: Settings.store) var dstarModule = "B"
    // AllStar: our registered node credentials plus the node to link to
    @AppStorage("aslMyNode", store: Settings.store) var aslMyNode = ""
    @AppStorage("aslPassword", store: Settings.store) var aslPassword = ""
    @AppStorage("aslTarget", store: Settings.store) var aslTarget = ""
    // Open Terminal only: probe all masters at connect and use the fastest.
    // "Master" is BrandMeister's own term for its servers.
    // swiftlint:disable:next inclusive_language
    @AppStorage("autoMaster", store: Settings.store) var autoMaster = true
    @AppStorage("txTargetTG", store: Settings.store) var txTargetTG = 0
    // Default: exactly one talkgroup subscribed at a time; going live on
    // one switches the others off. Turn off for multi-talkgroup monitoring.
    @AppStorage("singleTG", store: Settings.store) var singleTG = true
    // Push-to-talk style: false = hold to talk, true = tap to key up and
    // tap again to stop
    @AppStorage("pttToggle", store: Settings.store) var pttToggle = false
    // TX time-out timer in seconds; 0 disables it
    @AppStorage("txTimeoutSecs", store: Settings.store) var txTimeoutSecs = 120
    // QRZ XML API credentials for map geocoding; plain AppStorage matches
    // the existing hotspot-password precedent
    @AppStorage("qrzUser", store: Settings.store) var qrzUser = ""
    @AppStorage("qrzPassword", store: Settings.store) var qrzPassword = ""
    @AppStorage("mapOverlay", store: Settings.store) var mapOverlay = true
    // 0 = follow my subscribed talkgroups
    @AppStorage("mapOverlayTG", store: Settings.store) var mapOverlayTG = 0
    // Buddy watch: server-side push when watched callsigns key up
    @AppStorage("buddyWatchEnabled", store: Settings.store) var buddyWatchEnabled = false
    @AppStorage("buddyServerURL", store: Settings.store) var buddyServerURL = "https://dmr.carrierwave.app"
    @AppStorage("buddyAPIToken", store: Settings.store) var buddyAPIToken = ""
    @AppStorage("buddyDeviceID", store: Settings.store) var buddyDeviceID = ""
    @AppStorage("buddyLastToken", store: Settings.store) var buddyLastToken = ""
    @AppStorage("buddyLastSynced", store: Settings.store) var buddyLastSynced = ""
    @AppStorage("buddiesJSON", store: Settings.store) var buddiesJSON = ""
    @AppStorage("netsJSON", store: Settings.store) var netsJSON = ""
    // Saved destinations (see Destination.swift); the keys above stay the
    // working state the connect path reads
    @AppStorage("destinationsJSON", store: Settings.store) var destinationsJSON = ""
    @AppStorage("activeDestinationID", store: Settings.store) var activeDestinationID = ""

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
