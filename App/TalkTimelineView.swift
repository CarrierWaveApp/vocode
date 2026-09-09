import SwiftUI

/// One transmission drawn on a station's lane.
struct TalkBurst: Identifiable {
    let start: Date
    let end: Date?
    let dst: UInt32
    var channel: String?

    var id: Date { start }
}

/// One station row on the activity timeline. src 0 is ourselves.
struct StationLane: Identifiable {
    let src: UInt32
    let label: String
    let isSelf: Bool
    // False when src is a D-STAR callsign hash, not a radioid.net DMR ID
    var hasDMRID = true
    let note: CallNote?
    let bursts: [TalkBurst]

    var id: UInt32 { src }

    // Active bursts sort as future so live talkers float to the top
    var lastActivity: Date {
        bursts.map { $0.end ?? Date.distantFuture }.max() ?? .distantPast
    }
}

/// Rolling last-30-seconds view of who is talking, one lane per station,
/// derived from the heard list plus our own TX bursts. Tap a lane for the
/// station detail sheet.
struct TalkTimelineView: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var notes: CallNotesStore
    @State private var detail: StationLane?

    static let window: TimeInterval = 30
    static let retention: TimeInterval = 300
    static let maxLanes = 8
    private static let labelWidth: CGFloat = 92

    private let palette: [Color] = [
        CW.green, CW.amber, .purple, .cyan, CW.red, .pink, .mint, .indigo
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let lanes = makeLanes(now: timeline.date)
            if lanes.isEmpty {
                Text("Nothing heard in the last 5 minutes")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            } else {
                VStack(spacing: 7) {
                    ForEach(lanes) { lane in
                        laneRow(lane, now: timeline.date)
                    }
                    axisLabels
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $detail) { lane in
            StationDetailView(lane: lane, color: laneColor(lane))
        }
    }

    // MARK: - Lanes

    private func laneRow(_ lane: StationLane, now: Date) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                if let emoji = lane.note?.emoji {
                    Text(emoji).font(.system(size: 10))
                } else {
                    Circle().fill(laneColor(lane)).frame(width: 7, height: 7)
                }
                Text(lane.label)
                    .font(CW.mono(12, medium: lane.isSelf))
                    .foregroundStyle(lane.isSelf ? CW.white : CW.text)
                    .lineLimit(1)
            }
            .frame(width: Self.labelWidth, alignment: .leading)
            laneBar(lane, now: now)
                .frame(height: 18)
        }
        .contentShape(Rectangle())
        .onTapGesture { detail = lane }
    }

    private func laneBar(_ lane: StationLane, now: Date) -> some View {
        Canvas { canvas, size in
            let windowStart = now.addingTimeInterval(-Self.window)
            for burst in lane.bursts {
                let end = burst.end ?? now
                guard end > windowStart else { continue }
                let startX = max(0, CGFloat(burst.start.timeIntervalSince(windowStart) / Self.window) * size.width)
                let endX = min(size.width, CGFloat(end.timeIntervalSince(windowStart) / Self.window) * size.width)
                guard endX > startX else { continue }
                let rect = CGRect(x: startX, y: 2, width: max(2, endX - startX), height: size.height - 4)
                canvas.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(laneColor(lane)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(CW.raised))
        .overlay(alignment: .trailing) {
            Rectangle().fill(CW.red.opacity(0.7)).frame(width: 1)
        }
    }

    private var axisLabels: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.labelWidth, height: 1)
            HStack {
                Text("-30s")
                Spacer()
                Text("-15s")
                Spacer()
                Text("now")
            }
            .font(CW.mono(9))
            .foregroundStyle(CW.dim)
        }
    }

    private func laneColor(_ lane: StationLane) -> Color {
        lane.isSelf ? CW.blue : palette[Int(lane.src) % palette.count]
    }

    private func makeLanes(now: Date) -> [StationLane] {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var lanes: [StationLane] = []

        let myBursts = model.txBursts
            .filter { ($0.ended ?? now) > cutoff }
            .reversed()
            .map { TalkBurst(start: $0.started, end: $0.ended, dst: $0.dst, channel: $0.channel) }
        if !myBursts.isEmpty {
            let call = settings.callsign.trimmingCharacters(in: .whitespaces)
            lanes.append(StationLane(
                src: UInt32(settings.dmrID.trimmingCharacters(in: .whitespaces)) ?? 0,
                label: call.isEmpty ? "You" : call.uppercased(),
                isSelf: true,
                note: call.isEmpty ? nil : notes.note(for: call),
                bursts: myBursts
            ))
        }

        var bySrc: [UInt32: [HeardEntry]] = [:]
        for entry in model.heard where (entry.ended ?? now) > cutoff {
            bySrc[entry.src, default: []].append(entry)
        }
        let others = bySrc.compactMap { src, entries -> StationLane? in
            guard let latest = entries.first else { return nil }
            return StationLane(
                src: src,
                label: latest.callsign ?? String(src),
                isSelf: false,
                hasDMRID: !latest.dstar,
                note: entries.compactMap(\.note).first,
                bursts: entries.reversed().map {
                    TalkBurst(start: $0.started, end: $0.ended, dst: $0.dst, channel: $0.channel)
                }
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
        lanes.append(contentsOf: others.prefix(max(0, Self.maxLanes - lanes.count)))
        return lanes
    }
}

/// Enrichment sheet: radioid.net identity, callsign notes, and the
/// station's recent transmissions.
struct StationDetailView: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var notes: CallNotesStore
    @Environment(\.dismiss) private var dismiss
    let lane: StationLane
    let color: Color
    @State private var info: CallsignInfo?

    // Fall back to a lookup on the radioid-resolved callsign, which covers
    // our own lane when the callsign field is empty (Open Terminal mode)
    private var displayedNote: CallNote? {
        lane.note ?? info.flatMap { notes.note(for: $0.callsign) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(lane.label)
                            .font(CW.mono(22, medium: true))
                            .foregroundStyle(CW.white)
                        Spacer()
                        if lane.src != 0, lane.hasDMRID {
                            Text(String(lane.src))
                                .font(CW.mono(13))
                                .foregroundStyle(CW.dim)
                        }
                    }
                    if let call = info?.callsign, call.uppercased() != lane.label.uppercased() {
                        detailRow("Callsign", call)
                    }
                    if let name = info?.name {
                        detailRow("Name", name)
                    }
                    if let location = info?.location {
                        detailRow("Location", location)
                    }
                    if lane.src != 0, lane.hasDMRID, info == nil {
                        Text("Looking up radioid.net…")
                            .font(CW.mono(12))
                            .foregroundStyle(CW.dim)
                    }
                } header: {
                    SectionLabel("Station")
                }
                if let note = displayedNote {
                    Section {
                        Text(markdown(note.text))
                            .font(CW.sans(14))
                            .foregroundStyle(CW.text)
                    } header: {
                        SectionLabel("Notes")
                    } footer: {
                        Text(note.source)
                            .font(CW.mono(10))
                            .foregroundStyle(CW.dim)
                    }
                }
                Section {
                    ForEach(lane.bursts.reversed()) { burst in
                        burstRow(burst)
                    }
                } header: {
                    SectionLabel("Transmissions")
                }
            }
            .cwList()
            .navigationTitle(lane.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard lane.src != 0, lane.hasDMRID else { return }
                info = await model.stationInfo(lane.src)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func burstRow(_ burst: TalkBurst) -> some View {
        HStack {
            Text(burst.start.formatted(date: .omitted, time: .standard))
                .font(CW.mono(13))
                .foregroundStyle(CW.text)
            Text(settings.tgName(burst.dst) ?? burst.channel ?? "TG \(burst.dst)")
                .font(CW.sans(13))
                .foregroundStyle(CW.dim)
            Spacer()
            if let end = burst.end {
                Text("\(Int(end.timeIntervalSince(burst.start).rounded()))s")
                    .font(CW.mono(13))
                    .foregroundStyle(CW.dim)
            } else {
                Text("on air")
                    .font(CW.mono(13, medium: true))
                    .foregroundStyle(CW.green)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(CW.sans(14))
                .foregroundStyle(CW.dim)
            Spacer()
            Text(value)
                .font(CW.sans(14))
                .foregroundStyle(CW.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }
}
