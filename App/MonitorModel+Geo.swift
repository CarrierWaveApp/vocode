import Foundation

// QRZ geocoding for the station map
extension MonitorModel {
    func applyQRZ(_ settings: Settings) {
        Task { await qrz.configure(username: settings.qrzUser, password: settings.qrzPassword) }
    }

    // Attach QRZ coordinates to a heard entry; re-find by id after each
    // await since the entry may have been evicted meanwhile
    func geocode(streamID: UInt32, callsign call: String) async {
        guard await qrz.isConfigured,
              let station = await qrz.station(for: call),
              let point = station.bestPoint,
              let index = heard.firstIndex(where: { $0.id == streamID })
        else { return }
        heard[index].point = point
        heard[index].geoSource = station.source
    }

    // One-shot geocode of entries created before QRZ was configured;
    // serial on purpose — the actor's throttle paces the requests
    func backfillCoordinates() async {
        guard await qrz.isConfigured else { return }
        let wanted = heard.filter { $0.point == nil && $0.callsign != nil }
        var seen = Set<String>()
        for entry in wanted.prefix(40) {
            guard let call = entry.callsign, seen.insert(call).inserted else { continue }
            await geocode(streamID: entry.id, callsign: call)
        }
        await qrz.flush()
    }
}
