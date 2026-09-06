import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings
    @State private var showSettings = false
    @AppStorage("tgCollapsed") private var tgCollapsed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow
                    NavigationLink {
                        LogView()
                    } label: {
                        HStack {
                            Text("Connection log")
                            Spacer()
                            if let last = model.log.first {
                                Text(last.line)
                                    .font(CW.mono(11))
                                    .foregroundStyle(last.isError ? CW.red : CW.dim)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Section {
                    tgHeader
                    if !tgCollapsed {
                        ForEach(settings.talkgroupList.filter { $0.tg > 0 }) { tg in
                            TGRow(
                                tg: tg,
                                isTX: settings.txTargetTG == Int(tg.tg),
                                cycle: {
                                    settings.cycleListen(tg.tg)
                                    model.applyListenStates(settings)
                                },
                                selectTX: {
                                    guard tg.listen == .live else { return }
                                    settings.txTargetTG =
                                        settings.txTargetTG == Int(tg.tg) ? 0 : Int(tg.tg)
                                }
                            )
                        }
                    }
                } header: {
                    SectionLabel("Talkgroups")
                } footer: {
                    if !tgCollapsed, !settings.talkgroupList.isEmpty {
                        Text("tap speaker to cycle live → muted → off · tap TX to set the talk target")
                            .font(CW.mono(11))
                            .foregroundStyle(CW.dim)
                    }
                }
                Section {
                    if model.heard.isEmpty {
                        Text("Nothing heard yet")
                            .foregroundStyle(CW.dim)
                    }
                    ForEach(model.heard) { entry in
                        HeardRow(
                            entry: entry,
                            muted: model.isSilenced(entry.dst),
                            tgName: settings.tgName(entry.dst)
                        )
                            .swipeActions {
                                Button(model.isSilenced(entry.dst) ? "Unmute TG" : "Mute TG") {
                                    if let state = settings.listenState(entry.dst) {
                                        settings.setListen(entry.dst, state == .live ? .muted : .live)
                                        model.applyListenStates(settings)
                                    } else {
                                        model.toggleMute(entry.dst)
                                    }
                                }
                                .tint(CW.amber)
                            }
                    }
                } header: {
                    SectionLabel("Last heard")
                }
            }
            .cwList()
            .safeAreaInset(edge: .bottom) {
                if model.isConnected {
                    TalkBar(
                        target: settings.txTarget,
                        armed: settings.txTarget?.listen == .live,
                        transmitting: model.transmitting,
                        onPress: { model.beginTransmit(settings) },
                        onRelease: { model.endTransmit() }
                    )
                }
            }
            .navigationTitle("DMR Monitor")
            .toolbarBackground(CW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { model.clearHeard() }
                        .font(CW.sans(15))
                        .disabled(model.heard.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tgHeader: some View {
        let list = settings.talkgroupList.filter { $0.tg > 0 }
        let live = list.filter { $0.listen == .live }.count
        let mutedCount = list.filter { $0.listen == .muted }.count
        let off = list.filter { $0.listen == .off }.count

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { tgCollapsed.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tgCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CW.dim)
                if tgCollapsed, let lead = settings.txTarget ?? list.first(where: { $0.listen == .live }) {
                    Text(lead.name.isEmpty ? "TG \(lead.tg)" : lead.name)
                        .font(CW.sans(14, .medium))
                        .foregroundStyle(CW.white)
                    if list.count > 1 {
                        Text("+\(list.count - 1)")
                            .font(CW.sans(14))
                            .foregroundStyle(CW.dim)
                    }
                } else {
                    Text("\(list.count) talkgroup\(list.count == 1 ? "" : "s")")
                        .font(CW.sans(14, .medium))
                        .foregroundStyle(CW.white)
                }
                Spacer()
                HStack(spacing: 8) {
                    countDot(live, CW.green)
                    countDot(mutedCount, CW.amber)
                    countDot(off, CW.xdim)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func countDot(_ n: Int, _ color: Color) -> some View {
        if n > 0 {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(n)")
                    .font(CW.mono(10))
                    .foregroundStyle(CW.dim)
            }
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.isConnected ? CW.green : CW.xdim)
                    .frame(width: 8, height: 8)
                Text(model.link.label)
                    .font(CW.sans(15, .medium))
                    .foregroundStyle(model.isConnected ? CW.white : CW.text)
                Spacer()
                Button(model.isConnected ? "Disconnect" : "Connect") {
                    if model.isConnected {
                        model.disconnect()
                    } else {
                        model.connect(settings)
                    }
                }
                .buttonStyle(PillButtonStyle(filled: !model.isConnected))
            }
            if let err = model.audioError {
                Text(err).font(CW.sans(12)).foregroundStyle(CW.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TGRow: View {
    let tg: Talkgroup
    let isTX: Bool
    let cycle: () -> Void
    let selectTX: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: cycle) {
                Image(systemName: stateIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(stateColor)
                    .frame(width: 34, height: 34)
                    .background(CW.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(tg.listen == .off ? CW.border : stateColor.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(tg.name.isEmpty ? "TG \(tg.tg)" : tg.name)
                    .font(CW.sans(15, .medium))
                    .foregroundStyle(tg.listen == .off ? CW.dim : CW.white)
                Text("TG \(tg.tg) · \(tg.listen.rawValue.uppercased())")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
            Spacer()
            Button(action: selectTX) {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(isTX ? CW.blue : CW.xdim, lineWidth: 2)
                            .frame(width: 18, height: 18)
                        if isTX {
                            Circle().fill(CW.blue).frame(width: 9, height: 9)
                        }
                    }
                    Text("TX")
                        .font(CW.mono(9))
                        .foregroundStyle(CW.dim)
                }
                .opacity(tg.listen == .live || isTX ? 1 : 0.35)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var stateIcon: String {
        switch tg.listen {
        case .live: return "speaker.wave.2.fill"
        case .muted: return "speaker.slash.fill"
        case .off: return "power"
        }
    }

    private var stateColor: Color {
        switch tg.listen {
        case .live: return CW.green
        case .muted: return CW.amber
        case .off: return CW.xdim
        }
    }
}

struct TalkBar: View {
    let target: Talkgroup?
    let armed: Bool
    let transmitting: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(transmitting ? CW.red : (armed ? CW.blue : CW.xdim))
                .symbolEffect(.pulse, isActive: transmitting)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.map { $0.name.isEmpty ? "TG \($0.tg)" : $0.name } ?? "No TX target")
                    .font(CW.sans(14, .semibold))
                    .foregroundStyle(target != nil ? CW.white : CW.dim)
                Text(subtitle)
                    .font(CW.mono(10))
                    .tracking(0.8)
                    .foregroundStyle(CW.dim)
            }
            Spacer()
            Text(transmitting ? "On air" : "Hold to talk")
                .font(CW.sans(13, .medium))
                .foregroundStyle(transmitting ? CW.white : (armed ? CW.bg : CW.text))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(transmitting ? CW.red : (armed ? CW.blue : CW.raised))
                .overlay(Capsule().stroke(armed || transmitting ? .clear : CW.border, lineWidth: 1))
                .clipShape(Capsule())
                .opacity(armed || transmitting ? 1 : 0.45)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if armed, !transmitting { onPress() }
                        }
                        .onEnded { _ in onRelease() }
                )
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(CW.raised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CW.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var subtitle: String {
        guard let target else { return "SELECT IN TALKGROUPS" }
        if transmitting { return "TRANSMITTING · TG \(target.tg)" }
        return target.listen == .live
            ? "TX TARGET · TG \(target.tg)"
            : "TX DISARMED · TG \(target.tg)"
    }
}

struct LogView: View {
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        List {
            if model.log.isEmpty {
                Text("Nothing logged yet")
                    .foregroundStyle(CW.dim)
            }
            ForEach(model.log) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                    Text(entry.line)
                        .font(CW.mono(12))
                        .foregroundStyle(entry.isError ? CW.red : CW.text)
                }
                .padding(.vertical, 1)
            }
        }
        .cwList()
        .navigationTitle("Connection log")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { model.clearLog() }
                    .font(CW.sans(15))
                    .disabled(model.log.isEmpty)
            }
        }
    }
}

struct HeardRow: View {
    let entry: HeardEntry
    let muted: Bool
    var tgName: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let emoji = entry.note?.emoji {
                        Text(emoji).font(.system(size: 14))
                    }
                    Text(entry.callsign ?? String(entry.src))
                        .font(entry.callsign == nil ? CW.mono(15, medium: true) : CW.sans(17, .semibold))
                        .foregroundStyle(CW.white)
                    if entry.callsign != nil {
                        Text(String(entry.src))
                            .font(CW.mono(11))
                            .foregroundStyle(CW.dim)
                    }
                    Tag(tgName ?? "TG \(entry.dst)", color: muted ? CW.amber : CW.blue)
                    if entry.slot > 0 {
                        Tag("TS\(entry.slot)", color: CW.dim)
                    }
                    if muted {
                        Text("muted").font(CW.mono(11)).foregroundStyle(CW.amber)
                    }
                }
                if let note = entry.note {
                    Text(markdown(note.text))
                        .font(CW.sans(13))
                        .foregroundStyle(CW.text)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if entry.isActive {
                    Image(systemName: "waveform")
                        .foregroundStyle(CW.green)
                        .symbolEffect(.variableColor.iterative)
                } else {
                    Text(duration)
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                }
                Text(entry.started, style: .time)
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
        }
        .padding(.vertical, 1)
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    private var duration: String {
        let s = Int((entry.ended ?? Date()).timeIntervalSince(entry.started))
        return s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }
}

struct Tag: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(CW.mono(11))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CW.raised)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(CW.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel
    @Environment(\.dismiss) private var dismiss

    private var tgList: Binding<[Talkgroup]> {
        Binding(
            get: { settings.talkgroupList },
            set: { settings.talkgroupList = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Protocol", selection: settings.$netMode) {
                        Text("Open Terminal (BM)").tag("openterminal")
                        Text("Homebrew (hotspot)").tag("homebrew")
                    }
                    TextField("Host", text: settings.$host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(CW.mono(14))
                    if settings.netMode == "homebrew" {
                        TextField("Port", value: settings.$port, format: .number)
                            .keyboardType(.numberPad)
                            .font(CW.mono(14))
                    } else {
                        TextField("Port", value: settings.$otpPort, format: .number)
                            .keyboardType(.numberPad)
                            .font(CW.mono(14))
                    }
                } header: {
                    SectionLabel("Master")
                }
                Section {
                    TextField("DMR ID", text: settings.$dmrID)
                        .keyboardType(.numberPad)
                        .font(CW.mono(14))
                    SecureField("Hotspot password", text: settings.$password)
                    if settings.netMode == "homebrew" {
                        TextField("Callsign", text: settings.$callsign)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(CW.mono(14))
                        TextField("Hotspot suffix", text: settings.$suffix)
                            .keyboardType(.numberPad)
                            .font(CW.mono(14))
                        TextField("Location", text: settings.$location)
                    }
                } header: {
                    SectionLabel("Station")
                }
                Section {
                    NavigationLink("Callsign notes") { CallNotesView() }
                } header: {
                    SectionLabel("Data")
                }
                Section {
                    ForEach(tgList) { $tg in
                        HStack(spacing: 12) {
                            TextField("TG", text: Binding(
                                get: { tg.tg == 0 ? "" : String(tg.tg) },
                                set: { tg.tg = UInt32($0.filter(\.isNumber)) ?? 0 }
                            ))
                            .keyboardType(.numberPad)
                            .font(CW.mono(14))
                            .frame(width: 76)
                            TextField("Name", text: $tg.name)
                        }
                    }
                    .onDelete { tgList.wrappedValue.remove(atOffsets: $0) }
                    Button {
                        tgList.wrappedValue.append(Talkgroup(tg: 0, name: ""))
                    } label: {
                        Label("Add talkgroup", systemImage: "plus")
                            .font(CW.sans(15))
                    }
                } header: {
                    SectionLabel("Talkgroups")
                } footer: {
                    Text("Applied on next connect. Swipe to delete.")
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                }
                Section {
                    Toggle("Single talkgroup", isOn: settings.$singleTG)
                        .onChange(of: settings.singleTG) { _, on in
                            if on {
                                settings.enforceSingleLive()
                                model.applyListenStates(settings)
                            }
                        }
                } header: {
                    SectionLabel("Behavior")
                } footer: {
                    Text("Going live on a talkgroup switches the others off. Turn off to monitor several at once.")
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                }
            }
            .cwList()
            .navigationTitle("Settings")
            .toolbarBackground(CW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
