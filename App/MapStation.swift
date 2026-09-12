import Foundation

// MARK: - MapStation

/// One map pin: a station, merged from the local heard list and the
/// BrandMeister overlay. Pure logic, no UI.
struct MapStation: Identifiable, Equatable {
    enum Kind { case local, overlay }

    let id: String
    let callsign: String
    let name: String?
    let dmrID: UInt32
    let talkgroup: UInt32
    let channel: String?
    let point: GeoPoint
    let source: GeoSource
    let lastHeard: Date
    let active: Bool
    let kind: Kind

    func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastHeard))
    }
}

// MARK: - MapStationMerge

enum MapStationMerge {
    // MARK: Internal

    /// One pin per station: collapse local entries by src (list is
    /// newest-first), drop anything without coordinates or past TTL, and
    /// let a local pin win over its overlay duplicate.
    static func stations(
        heard: [HeardEntry],
        overlay: [UInt32: BMStation],
        now: Date,
        localTTL: TimeInterval,
        overlayTTL: TimeInterval
    ) -> [MapStation] {
        var localIDs = Set<UInt32>()
        var localCalls = Set<String>()
        var result = localStations(
            heard,
            now: now,
            localTTL: localTTL,
            localIDs: &localIDs,
            localCalls: &localCalls
        )
        result += overlayStations(
            overlay,
            now: now,
            overlayTTL: overlayTTL,
            localIDs: localIDs,
            localCalls: localCalls
        )
        return result
    }

    // MARK: Private

    /// One pin per still-relevant local entry, and the set of src IDs and
    /// uppercased callsigns claimed, so the overlay pass can defer to them.
    private static func localStations(
        _ heard: [HeardEntry],
        now: Date,
        localTTL: TimeInterval,
        localIDs: inout Set<UInt32>,
        localCalls: inout Set<String>
    ) -> [MapStation] {
        var result: [MapStation] = []
        for entry in heard {
            guard localIDs.insert(entry.src).inserted else {
                continue
            }
            guard let point = entry.point, let call = entry.callsign else {
                continue
            }
            let lastHeard = entry.ended ?? now
            guard entry.isActive || now.timeIntervalSince(lastHeard) < localTTL else {
                continue
            }
            localCalls.insert(call.uppercased())
            result.append(MapStation(
                id: "L\(entry.src)",
                callsign: call,
                name: nil,
                dmrID: entry.dstar ? 0 : entry.src,
                talkgroup: entry.dst,
                channel: entry.channel,
                point: point,
                source: entry.geoSource ?? .qrz,
                lastHeard: lastHeard,
                active: entry.isActive,
                kind: .local
            ))
        }
        return result
    }

    /// One pin per overlay station not already covered by a local pin.
    private static func overlayStations(
        _ overlay: [UInt32: BMStation],
        now: Date,
        overlayTTL: TimeInterval,
        localIDs: Set<UInt32>,
        localCalls: Set<String>
    ) -> [MapStation] {
        var result: [MapStation] = []
        for station in overlay.values {
            guard let point = station.point,
                  !localIDs.contains(station.dmrID),
                  !localCalls.contains(station.callsign),
                  station.active || now.timeIntervalSince(station.lastHeard) < overlayTTL
            else {
                continue
            }
            result.append(MapStation(
                id: "B\(station.dmrID)",
                callsign: station.callsign,
                name: station.name,
                dmrID: station.dmrID,
                talkgroup: station.talkgroup,
                channel: nil,
                point: point,
                source: station.geoSource ?? .qrz,
                lastHeard: station.lastHeard,
                active: station.active,
                kind: .overlay
            ))
        }
        return result
    }
}
