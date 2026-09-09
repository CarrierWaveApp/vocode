import Foundation

// Seeds the last-heard list from BrandMeister's lastheard history, so
// opening or connecting the app shows recent talking instead of an
// empty list that only fills while connected.
extension MonitorModel {
    func refreshHistory(_ settings: Settings) {
        let talkgroups = Set(settings.activeTalkgroups)
        // BM history only makes sense against BrandMeister
        guard !talkgroups.isEmpty,
              settings.netMode == "openterminal"
                || settings.host.contains("brandmeister"),
              Date().timeIntervalSince(lastHistorySeed) > 60
        else { return }
        lastHistorySeed = Date()

        // One-shot: connect, let the backlog (searchHouse) and a few live
        // seconds arrive, then tear down and seed
        let feed = BrandmeisterLH(talkgroups: talkgroups)
        historyFeed = feed
        var collected: [BMCall] = []
        feed.onCalls = { calls in
            Task { @MainActor in collected.append(contentsOf: calls) }
        }
        feed.connect()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            feed.disconnect()
            guard let self, self.historyFeed === feed else { return }
            self.historyFeed = nil
            self.seedHistory(collected)
        }
    }

    private func seedHistory(_ history: [BMCall]) {
        guard !history.isEmpty else { return }
        var counter: UInt32 = 0xF000_0000 | UInt32(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100_000))
        var list = heard
        var added = 0
        for call in history {
            let duplicate = list.contains { entry in
                entry.src == call.sourceID
                    && abs(entry.started.timeIntervalSince(call.began)) < 2
            }
            guard !duplicate else { continue }
            counter &+= 1
            var entry = HeardEntry(
                id: counter, src: call.sourceID, dst: call.destinationID,
                slot: 0, started: call.began
            )
            // Seeds always render as ended — a phantom "active" row with
            // no audio behind it would be confusing
            entry.ended = max(call.began, call.time)
            entry.callsign = call.sourceCall.isEmpty ? nil : call.sourceCall
            if let known = entry.callsign {
                entry.note = notes.note(for: known)
            }
            list.append(entry)
            added += 1
        }
        guard added > 0 else { return }
        list.sort { $0.started > $1.started }
        if list.count > 200 {
            list = Array(list.prefix(200))
        }
        heard = list
        appendLog("seeded \(added) calls from BM history")

        // Resolve missing callsigns (Open Terminal callers ship blank
        // ones) and map coordinates for the new entries
        for entry in list.prefix(30) where entry.callsign == nil {
            Task { [entryID = entry.id, src = entry.src] in
                guard let info = await stationInfo(src),
                      let index = heard.firstIndex(where: { $0.id == entryID })
                else { return }
                heard[index].callsign = info.callsign
                heard[index].note = notes.note(for: info.callsign)
                await geocode(streamID: entryID, callsign: info.callsign)
            }
        }
        Task { await backfillCoordinates() }
    }
}
