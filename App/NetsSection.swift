import SwiftUI

/// Main-screen "// NETS" card: the next couple of upcoming nets with a
/// countdown and one-tap Join. body IS a Section so ContentView only
/// inserts `NetsSection()`.
struct NetsSection: View {
    // MARK: Internal

    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        Section {
            if upcoming.isEmpty {
                NavigationLink {
                    NetsView()
                } label: {
                    Text(settings.netList.isEmpty
                        ? "Add nets to get reminders"
                        : "No upcoming nets")
                        .font(CW.sans(15))
                        .foregroundStyle(CW.dim)
                }
            } else {
                ForEach(upcoming, id: \.net.id) { entry in
                    row(entry.net, start: entry.start)
                }
                NavigationLink("All nets (\(settings.netList.count))") {
                    NetsView()
                }
                .font(CW.sans(14))
                .foregroundStyle(CW.dim)
            }
        } header: {
            SectionLabel("Nets")
        }
    }

    // MARK: Private

    /// Next two enabled nets by start time; recomputed on each timeline tick
    private var upcoming: [(net: Net, start: Date)] {
        let now = Date()
        return settings.netList
            .filter { $0.enabled && $0.talkgroup > 0 && !$0.weekdays.isEmpty }
            .compactMap { net in
                NetSchedule.nextOccurrence(of: net, after: now).map { (net, $0) }
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
