import Foundation
import SwiftUI
import UserNotifications

// Schedules the repeating local reminders for nets. iOS silently keeps
// only the 64 soonest pending requests, so the expansion is capped
// deterministically in list order and surfaced in the UI.
@MainActor
enum NetScheduler {
    static let maxRequests = 64
    static let joinCategory = "NET"
    static let joinAction = "NET_JOIN"
    static let pendingTGKey = "pendingJoinTG"
    static let pendingNameKey = "pendingJoinName"
    static let joinRequested = Notification.Name("netJoinRequested")

    // Full rebuild: remove every net.* request, re-add up to the cap.
    // Returns (scheduled, trimmed) for the footer.
    @discardableResult
    static func reschedule(_ nets: [Net], tgName: (UInt32) -> String?) async -> (Int, Int) {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix("net.") }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        var requests: [UNNotificationRequest] = []
        var trimmed = 0
        let now = Date()
        for net in nets where net.enabled && net.talkgroup > 0 && !net.weekdays.isEmpty {
            for weekday in net.weekdays {
                for lead in net.leads.sorted(by: >) {
                    if requests.count >= maxRequests {
                        trimmed += 1
                        continue
                    }
                    if let request = request(
                        for: net, weekday: weekday, lead: lead,
                        now: now, tgLabel: tgName(net.talkgroup)
                    ) {
                        requests.append(request)
                    }
                }
            }
        }
        for request in requests {
            try? await center.add(request)
        }
        return (requests.count, trimmed)
    }

    private static func request(
        for net: Net, weekday: Int, lead: Int, now: Date, tgLabel: String?
    ) -> UNNotificationRequest? {
        // Compute the concrete next start for THIS weekday, subtract the
        // lead, and read the fire components back off the real date —
        // that makes a lead crossing midnight land on the right weekday
        var only = net
        only.weekdays = [weekday]
        guard let start = NetSchedule.nextOccurrence(of: only, after: now) else {
            return nil
        }
        let fire = start.addingTimeInterval(-Double(lead) * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = net.timeZone
        var comps = calendar.dateComponents([.weekday, .hour, .minute], from: fire)
        // Trigger honors DateComponents.timeZone (unlike Calendar.nextDate,
        // which wants the zone on the calendar)
        comps.timeZone = net.timeZone

        let content = UNMutableNotificationContent()
        content.title = "Net: \(net.name.isEmpty ? "TG \(net.talkgroup)" : net.name)"
        let tgText = tgLabel.map { "TG \(net.talkgroup) \($0)" } ?? "TG \(net.talkgroup)"
        content.body = lead == 0
            ? "\(tgText) · starting now"
            : "\(tgText) · starts in \(lead) min"
        content.sound = .default
        content.categoryIdentifier = joinCategory
        content.threadIdentifier = "nets"
        content.userInfo = [
            "kind": "net",
            "netID": net.id.uuidString,
            "tg": Int(net.talkgroup),
            "name": net.name
        ]
        return UNNotificationRequest(
            identifier: "net.\(net.id.uuidString).\(weekday).\(lead)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        )
    }

    static func pendingNetRequestCount() async -> Int {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix("net.") }.count
    }
}

// One-tap join: make the net's talkgroup live and get audio flowing
@MainActor
enum NetJoin {
    static func join(talkgroup: UInt32, name: String, settings: Settings, model: MonitorModel) {
        guard talkgroup > 0, settings.netMode != "dstar",
              settings.netMode != "allstar" else { return }
        if !settings.talkgroupList.contains(where: { $0.tg == talkgroup }) {
            // .off first: setListen bails on a TG it can't find
            settings.talkgroupList.append(Talkgroup(tg: talkgroup, name: name, listen: .off))
        }
        settings.setListen(talkgroup, .live)
        if model.isConnected, settings.netMode == "openterminal" {
            // Open Terminal diffs subscriptions live; homebrew ships its
            // talkgroups at login, so it needs a reconnect
            model.applyListenStates(settings)
        } else {
            model.connect(settings)
        }
    }
}

// Root-level relay: consumes join intents from notification taps. Lives
// on the app root (never unloaded) rather than a lazy List section.
struct NetJoinRelay: ViewModifier {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { drain() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { drain() }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NetScheduler.joinRequested)) { _ in
                drain()
            }
    }

    private func drain() {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: NetScheduler.pendingTGKey)
        guard stored > 0 else { return }
        let name = defaults.string(forKey: NetScheduler.pendingNameKey) ?? ""
        defaults.removeObject(forKey: NetScheduler.pendingTGKey)
        defaults.removeObject(forKey: NetScheduler.pendingNameKey)
        NetJoin.join(talkgroup: UInt32(stored), name: name, settings: settings, model: model)
    }
}
