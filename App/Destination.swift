import Foundation

// MARK: - DestinationKind

enum DestinationKind: String, Codable, CaseIterable, Identifiable {
    case brandmeister
    case hotspot
    case dstar
    case allstar

    // MARK: Lifecycle

    init(netMode: String) {
        switch netMode {
        case "homebrew": self = .hotspot
        case "dstar": self = .dstar
        case "allstar": self = .allstar
        default: self = .brandmeister
        }
    }

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// The legacy `netMode` working key the connect path switches on
    var netMode: String {
        switch self {
        case .brandmeister: "openterminal"
        case .hotspot: "homebrew"
        case .dstar: "dstar"
        case .allstar: "allstar"
        }
    }

    var label: String {
        switch self {
        case .brandmeister: "DMR · BrandMeister"
        case .hotspot: "DMR · Hotspot"
        case .dstar: "D-STAR"
        case .allstar: "AllStar"
        }
    }

    var isDMR: Bool {
        self == .brandmeister || self == .hotspot
    }
}

// MARK: - Destination

/// A saved place to connect: a BrandMeister master plus talkgroups, a
/// hotspot, an XLX reflector module, or an AllStar node. Works like a
/// radio's memory channels: activating one loads its fields into the
/// working `Settings` keys the connect path reads, and the previously
/// active destination gets the current keys written back first.
struct Destination: Codable, Identifiable, Equatable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), kind: DestinationKind, name: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(DestinationKind.self, forKey: .kind) ?? .brandmeister
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 62_031
        otpPort = try container.decodeIfPresent(Int.self, forKey: .otpPort) ?? 54_006
        autoMaster = try container.decodeIfPresent(Bool.self, forKey: .autoMaster) ?? true
        module = try container.decodeIfPresent(String.self, forKey: .module) ?? "B"
        node = try container.decodeIfPresent(String.self, forKey: .node) ?? ""
        talkgroups = try container.decodeIfPresent([Talkgroup].self, forKey: .talkgroups) ?? []
        txTargetTG = try container.decodeIfPresent(Int.self, forKey: .txTargetTG) ?? 0
    }

    // MARK: Internal

    var id: UUID
    var kind: DestinationKind
    var name: String
    /// Server host for BrandMeister, hotspot, and D-STAR; unused for AllStar
    var host = ""
    /// Homebrew port (hotspot only)
    var port = 62_031
    /// Open Terminal port (BrandMeister only)
    var otpPort = 54_006
    // BrandMeister only: probe all masters at connect and use the fastest.
    // ("Master" is BrandMeister's own term for its servers.)
    // swiftlint:disable:next inclusive_language
    var autoMaster = true
    /// D-STAR module letter
    var module = "B"
    /// AllStar node number to link to
    var node = ""
    /// DMR kinds only
    var talkgroups: [Talkgroup] = []
    var txTargetTG = 0

    /// Name for lists and the nav-bar switcher; falls back to a label
    /// derived from the target when the user hasn't named it
    var displayName: String {
        if !name.isEmpty {
            return name
        }
        switch kind {
        case .brandmeister:
            if autoMaster {
                return "BrandMeister"
            }
            // swiftlint:disable:next inclusive_language
            if let master = BMDirectory.master(forHost: host) {
                return "BM \(master.id) \(master.country)"
            }
            return host.isEmpty ? "BrandMeister" : host
        case .hotspot:
            return host.isEmpty ? "Hotspot" : host
        case .dstar:
            let trimmed = host.trimmingCharacters(in: .whitespaces)
            let reflector = XLXDirectory.reflector(forHost: trimmed)?.name
                ?? trimmed.split(separator: ".").first.map(String.init)?.uppercased()
            guard let reflector, !reflector.isEmpty else {
                return "D-STAR"
            }
            return "\(reflector) \(module.uppercased())"
        case .allstar:
            let trimmed = node.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "AllStar" : "Node \(trimmed)"
        }
    }

    /// Second line for destination rows: the kind plus target detail
    var summary: String {
        switch kind {
        case .brandmeister:
            let live = talkgroups.filter { $0.tg > 0 && $0.listen != .off }.count
            let tgs = live == 1 ? "1 talkgroup" : "\(live) talkgroups"
            return autoMaster ? "\(kind.label) · nearest · \(tgs)" : "\(kind.label) · \(tgs)"
        case .hotspot:
            return "\(kind.label) · \(host.isEmpty ? "no host" : "\(host):\(port)")"
        case .dstar:
            return "\(kind.label) · \(host.isEmpty ? "no reflector" : host)"
        case .allstar:
            // No directory lookup here: ASLDirectory is main-actor-bound
            // and this runs from nonisolated contexts
            return kind.label
        }
    }
}

// MARK: - Saved destinations over the working keys

extension Settings {
    /// Active destination kind, derived from the legacy netMode key
    var activeKind: DestinationKind {
        DestinationKind(netMode: netMode)
    }

    var destinations: [Destination] {
        get {
            guard let data = destinationsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Destination].self, from: data)
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
            destinationsJSON = json
        }
    }

    var activeDestination: Destination? {
        destinations.first { $0.id.uuidString == activeDestinationID }
    }

    /// Write the current working keys back into the active destination's
    /// saved slot, so edits made while it was active (talkgroup changes,
    /// net joins, auto-master host updates) survive switching away
    func snapshotActiveDestination() {
        var list = destinations
        guard let i = list.firstIndex(where: { $0.id.uuidString == activeDestinationID }) else {
            return
        }
        var dest = list[i]
        switch dest.kind {
        case .brandmeister:
            dest.host = host
            dest.otpPort = otpPort
            dest.autoMaster = autoMaster
            dest.talkgroups = talkgroupList
            dest.txTargetTG = txTargetTG
        case .hotspot:
            dest.host = host
            dest.port = port
            dest.talkgroups = talkgroupList
            dest.txTargetTG = txTargetTG
        case .dstar:
            dest.host = dstarHost
            dest.module = dstarModule
        case .allstar:
            dest.node = aslTarget
        }
        list[i] = dest
        destinations = list
    }

    /// Make `dest` the active destination: snapshot the old one, store
    /// `dest`, and load its fields into the working keys the connect
    /// path reads
    func activate(_ dest: Destination) {
        snapshotActiveDestination()
        upsert(dest)
        loadWorkingKeys(from: dest)
        activeDestinationID = dest.id.uuidString
    }

    /// Insert or replace by id, then refresh the working keys when the
    /// edited destination is the active one
    func applyEdits(_ dest: Destination) {
        upsert(dest)
        if dest.id.uuidString == activeDestinationID {
            loadWorkingKeys(from: dest)
        }
    }

    func delete(_ dest: Destination) {
        destinations.removeAll { $0.id == dest.id }
        if dest.id.uuidString == activeDestinationID {
            activeDestinationID = ""
        }
    }

    /// One-time migration from the flat pre-destination settings: one
    /// destination per configured system, active matching the old netMode
    func migrateDestinationsIfNeeded() {
        guard destinationsJSON.isEmpty else {
            return
        }
        let currentKind = DestinationKind(netMode: netMode)
        var list: [Destination] = []

        var dmr = Destination(kind: currentKind.isDMR ? currentKind : .brandmeister)
        dmr.host = host
        dmr.port = port
        dmr.otpPort = otpPort
        dmr.autoMaster = autoMaster
        dmr.talkgroups = talkgroupList
        dmr.txTargetTG = txTargetTG
        list.append(dmr)

        if !dstarHost.trimmingCharacters(in: .whitespaces).isEmpty || currentKind == .dstar {
            var dstar = Destination(kind: .dstar)
            dstar.host = dstarHost
            dstar.module = dstarModule
            list.append(dstar)
        }
        if !aslTarget.trimmingCharacters(in: .whitespaces).isEmpty || currentKind == .allstar {
            var allstar = Destination(kind: .allstar)
            allstar.node = aslTarget
            list.append(allstar)
        }

        destinations = list
        let active = list.first { $0.kind == currentKind } ?? list[0]
        activeDestinationID = active.id.uuidString
    }

    // MARK: Private

    private func upsert(_ dest: Destination) {
        var list = destinations
        if let i = list.firstIndex(where: { $0.id == dest.id }) {
            list[i] = dest
        } else {
            list.append(dest)
        }
        destinations = list
    }

    private func loadWorkingKeys(from dest: Destination) {
        netMode = dest.kind.netMode
        switch dest.kind {
        case .brandmeister:
            // An auto-master destination may carry no host; keep the
            // current one so rewindConfig stays valid until the probe
            // rewrites it at connect
            if !dest.host.isEmpty {
                host = dest.host
                otpPort = dest.otpPort
            }
            autoMaster = dest.autoMaster
            talkgroupList = dest.talkgroups
            txTargetTG = dest.txTargetTG
        case .hotspot:
            host = dest.host
            port = dest.port
            autoMaster = false
            talkgroupList = dest.talkgroups
            txTargetTG = dest.txTargetTG
        case .dstar:
            dstarHost = dest.host
            dstarModule = dest.module
        case .allstar:
            aslTarget = dest.node
        }
    }
}
