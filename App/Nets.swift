import Foundation

// One scheduled net. `id` is the merge key for share/import: a club
// re-publishing its schedule updates in place instead of duplicating.
struct Net: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var network: String
    var talkgroup: UInt32
    // Calendar weekday numbering: 1 = Sunday … 7 = Saturday
    var weekdays: [Int]
    // Wall-clock start in `timeZoneID` — nets are published in a fixed
    // zone, so a device travelling doesn't shift the net
    var hour: Int
    var minute: Int
    var timeZoneID: String
    var durationMin: Int
    // Reminder lead times in minutes; 0 = at start
    var leads: [Int]
    var enabled: Bool
    var notes: String

    init(id: UUID = UUID(), name: String = "", network: String = "BrandMeister",
         talkgroup: UInt32 = 0, weekdays: [Int] = [], hour: Int = 19, minute: Int = 0,
         timeZoneID: String = TimeZone.current.identifier, durationMin: Int = 60,
         leads: [Int] = [10], enabled: Bool = true, notes: String = "") {
        self.id = id
        self.name = name
        self.network = network
        self.talkgroup = talkgroup
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
        self.timeZoneID = timeZoneID
        self.durationMin = durationMin
        self.leads = leads
        self.enabled = enabled
        self.notes = notes
    }

    // Lenient like Talkgroup: one malformed element must not throw away
    // an entire imported list
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        network = try values.decodeIfPresent(String.self, forKey: .network) ?? ""
        talkgroup = try values.decodeIfPresent(UInt32.self, forKey: .talkgroup) ?? 0
        weekdays = try values.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        hour = try values.decodeIfPresent(Int.self, forKey: .hour) ?? 0
        minute = try values.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        timeZoneID = try values.decodeIfPresent(String.self, forKey: .timeZoneID)
            ?? TimeZone.current.identifier
        durationMin = try values.decodeIfPresent(Int.self, forKey: .durationMin) ?? 60
        leads = try values.decodeIfPresent([Int].self, forKey: .leads) ?? [10]
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    // "19:00" in the net's own zone
    var wallTime: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

// Share/import envelope; import also accepts a bare [Net] array
struct NetsFile: Codable {
    var version: Int
    var nets: [Net]
}

enum NetSchedule {
    // Next start after `now`. Zone goes on the CALENDAR here;
    // UNCalendarNotificationTrigger wants it on the DateComponents
    // instead — the two APIs have opposite conventions.
    static func nextOccurrence(of net: Net, after now: Date) -> Date? {
        occurrences(of: net, after: now, limit: 1).first
    }

    static func occurrences(of net: Net, after now: Date, limit: Int) -> [Date] {
        guard !net.weekdays.isEmpty, limit > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = net.timeZone
        var found: [Date] = []
        var cursor = now
        while found.count < limit {
            var candidates: [Date] = []
            for weekday in net.weekdays {
                let components = DateComponents(
                    hour: net.hour, minute: net.minute, weekday: weekday
                )
                if let date = calendar.nextDate(
                    after: cursor, matching: components, matchingPolicy: .nextTime
                ) {
                    candidates.append(date)
                }
            }
            guard let next = candidates.min() else { break }
            found.append(next)
            cursor = next
        }
        return found
    }

    // Within [start, start + duration) of the most recent occurrence
    static func isLive(_ net: Net, at now: Date) -> Bool {
        let lookback = now.addingTimeInterval(-Double(net.durationMin) * 60)
        guard let start = nextOccurrence(of: net, after: lookback) else { return false }
        return start <= now && now < start.addingTimeInterval(Double(net.durationMin) * 60)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "in \(minutes)m" }
        if minutes < 48 * 60 {
            return "in \(minutes / 60)h \(minutes % 60)m"
        }
        return "in \(minutes / 1440)d"
    }
}
