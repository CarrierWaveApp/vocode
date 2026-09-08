import Foundation
import Combine

// A station seen on the BrandMeister last-heard overlay
struct BMStation: Equatable {
    let dmrID: UInt32
    let callsign: String
    var name: String?
    var talkgroup: UInt32
    var lastHeard: Date
    var active: Bool
    var point: GeoPoint?
    var geoSource: GeoSource?
}

// Owns the BM last-heard socket and the overlay station set. Lives on
// MonitorModel so pins survive popping the map, but the socket only runs
// while the map is on screen (the raw stream is all of BrandMeister).
@MainActor
final class OverlayModel: ObservableObject {
    @Published private(set) var stations: [UInt32: BMStation] = [:]
    @Published private(set) var state: LinkState = .idle
    var log: ((String, Bool) -> Void)?

    private let qrz: QRZLookup
    private var client: BrandmeisterLH?
    private var geocodeTried: Set<String> = []
    private let maxStations = 300
    private let stationTTL: TimeInterval = 15 * 60
    // Force-clear "on air" when a Session-Stop never arrives
    private let activeTimeout: TimeInterval = 300

    init(qrz: QRZLookup) {
        self.qrz = qrz
    }

    var isRunning: Bool { client != nil }

    func start(talkgroups: Set<UInt32>) {
        if let client {
            client.setTalkgroups(talkgroups)
            return
        }
        guard !talkgroups.isEmpty else {
            state = .failed("no talkgroup")
            return
        }
        let feed = BrandmeisterLH(talkgroups: talkgroups)
        // Guard every callback by client identity: after a stop()/start()
        // cycle the old client's queued callbacks must not clobber the
        // new client's state
        feed.onState = { [weak self, weak feed] newState in
            Task { @MainActor in
                guard let self, self.client === feed else { return }
                self.state = newState
            }
        }
        feed.onLog = { [weak self] line, isError in
            Task { @MainActor in self?.log?(line, isError) }
        }
        feed.onCalls = { [weak self, weak feed] calls in
            Task { @MainActor in
                guard let self, self.client === feed else { return }
                self.apply(calls)
            }
        }
        client = feed
        feed.connect()
    }

    func stop() {
        client?.onState = nil
        client?.onCalls = nil
        client?.disconnect()
        client = nil
        state = .idle
    }

    // Clear pins so a talkgroup change doesn't leave stale stations behind
    func setTalkgroups(_ tgs: Set<UInt32>) {
        stations.removeAll()
        if let client {
            client.setTalkgroups(tgs)
        } else {
            start(talkgroups: tgs)
        }
    }

    func prune(now: Date) {
        for (key, station) in stations {
            if now.timeIntervalSince(station.lastHeard) > stationTTL {
                stations.removeValue(forKey: key)
            } else if station.active, now.timeIntervalSince(station.lastHeard) > activeTimeout {
                stations[key]?.active = false
            }
        }
    }

    private func apply(_ calls: [BMCall]) {
        for call in calls {
            var station = stations[call.sourceID] ?? BMStation(
                dmrID: call.sourceID, callsign: call.sourceCall, name: call.sourceName,
                talkgroup: call.destinationID, lastHeard: call.time, active: call.active,
                point: nil, geoSource: nil
            )
            // Backlog rows can arrive out of order; never regress a
            // station to an older call
            if call.time >= station.lastHeard {
                station.lastHeard = call.time
                station.active = call.active
                station.talkgroup = call.destinationID
            }
            if station.name == nil { station.name = call.sourceName }
            stations[call.sourceID] = station
            if station.point == nil { geocode(station) }
        }
        evict()
    }

    // One QRZ attempt per callsign per app session
    private func geocode(_ station: BMStation) {
        guard geocodeTried.insert(station.callsign).inserted else { return }
        Task {
            guard await qrz.isConfigured,
                  let info = await qrz.station(for: station.callsign),
                  let point = info.bestPoint else { return }
            stations[station.dmrID]?.point = point
            stations[station.dmrID]?.geoSource = info.source
        }
    }

    private func evict() {
        while stations.count > maxStations {
            guard let oldest = stations.min(by: { $0.value.lastHeard < $1.value.lastHeard })
            else { return }
            stations.removeValue(forKey: oldest.key)
        }
    }
}
