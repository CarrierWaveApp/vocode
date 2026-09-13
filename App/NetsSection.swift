import SwiftUI

/// Main-screen nets card: shown only when a net is live or starts within
/// the hour, so config noise stays out of the activity view. The full
/// list lives in Settings → Nets. body IS a Section (or nothing) so
/// ContentView only inserts `NetsSection()`.
struct NetsSection: View {
    // MARK: Internal

    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        if !upcoming.isEmpty {
            Section {
                ForEach(upcoming, id: \.net.id) { entry in
                    row(entry.net, start: entry.start)
                }
            } header: {
                SectionLabel("Nets")
            }
        }
    }

    // MARK: Private

    /// How far ahead a net may start and still earn main-screen space
    private static let window: TimeInterval = 3_600

    /// Up to two enabled nets that are live now or start within the window
    private var upcoming: [(net: Net, start: Date)] {
        let now = Date()
        return settings.netList
            .filter { $0.enabled && $0.talkgroup > 0 && !$0.weekdays.isEmpty }
            .compactMap { net -> (Net, Date)? in
                guard let start = NetSchedule.nextOccurrence(of: net, after: now) else {
                    return nil
                }
                guard NetSchedule.isLive(net, at: now)
                    || start.timeIntervalSince(now) <= Self.window
                else {
                    return nil
                }
                return (net, start)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(2)
            .map { (net: $0.0, start: $0.1) }
    }

    private func row(_ net: Net, start: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(net.name.isEmpty ? "TG \(String(net.talkgroup))" : net.name)
                        .font(CW.sans(15, .medium))
                    Text("TG \(String(net.talkgroup)) · \(net.wallTime) \(zoneLabel(net))")
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                }
                Spacer()
                if NetSchedule.isLive(net, at: context.date) {
                    Text("LIVE")
                        .font(CW.mono(11, medium: true))
                        .foregroundStyle(CW.green)
                } else {
                    Text(NetSchedule.countdown(to: start, from: context.date))
                        .font(CW.mono(11))
                        .foregroundStyle(CW.blue)
                }
                if settings.activeKind.isDMR {
                    Button("Join") {
                        NetJoin.join(talkgroup: net.talkgroup, name: net.name,
                                     settings: settings, model: model)
                    }
                    .buttonStyle(PillButtonStyle(filled: false))
                }
            }
        }
    }

    private func zoneLabel(_ net: Net) -> String {
        net.timeZone.abbreviation() ?? net.timeZoneID
    }
}
