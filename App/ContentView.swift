import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings
    @State private var showSettings = false
    @State private var showMap = false
    @StateObject private var buddyClient = BuddyClient()
    @State private var connExpanded = false
    @AppStorage("tgCollapsed") private var tgCollapsed = false

    var body: some View {
        NavigationStack {
            List {
                if !model.isConnected || connExpanded || model.audioError != nil {
                    Section {
                        statusRow
                        logLink
                        if let err = model.audioError {
                            Text(err).font(CW.sans(12)).foregroundStyle(CW.red)
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
                NetsSection()
                Section {
                    TalkTimelineView()
                } header: {
                    HStack {
                        SectionLabel("Activity")
                        Spacer()
                        if model.isConnected {
                            HStack(spacing: 4) {
                                Circle().fill(CW.green).frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(CW.mono(10, medium: true))
                                    .foregroundStyle(CW.green)
                            }
                        }
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
                    TalkBarHost()
                }
            }
            .navigationTitle("Vocode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerStatus
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { model.clearHeard() }
                        .font(CW.sans(15))
                        .disabled(model.heard.isEmpty)
                }
                // Button + navigationDestination: a NavigationLink directly
                // in a toolbar swallows taps on iOS 26
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMap = true
                    } label: {
                        Image(systemName: "map")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(isPresented: $showMap) {
                StationMapView(overlay: model.overlay)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .environmentObject(buddyClient)
        .task {
            buddyClient.startup(settings)
            model.refreshHistory(settings)
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

    /// Lives in the nav bar as the principal item: dot, summary, chevron.
    /// Tapping toggles the connection section in the list.
    private var headerStatus: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { connExpanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.isConnected ? CW.green : CW.xdim)
                    .frame(width: 8, height: 8)
                Text(model.isConnected ? settings.connectedSummary : model.link.label)
                    .font(CW.mono(13, medium: true))
                    .foregroundStyle(model.isConnected ? CW.white : CW.text)
                    .lineLimit(1)
                Image(systemName: connExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CW.dim)
            }
        }
        .buttonStyle(.plain)
    }

    private var logLink: some View {
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

    private var statusRow: some View {
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
                // String(tg) keeps Text's localized interpolation from
                // rendering 3100 as "3,100"
                Text("TG \(String(tg.tg)) · \(tg.listen.rawValue.uppercased())")
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

/// Picks the TX destination for the talk bar: the linked node on
/// AllStar, the selected talkgroup everywhere else
struct TalkBarHost: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        if settings.netMode == "allstar" {
            let node = settings.aslTarget.trimmingCharacters(in: .whitespaces)
            TalkBar(
                title: "Node \(node)",
                tag: "NODE \(node)",
                armed: true,
                transmitting: model.transmitting,
                onPress: { model.beginTransmit(settings) },
                onRelease: { model.endTransmit() }
            )
        } else {
            TalkBar(
                title: settings.txTarget.map { $0.name.isEmpty ? "TG \($0.tg)" : $0.name },
                tag: settings.txTarget.map { "TG \($0.tg)" },
                armed: settings.txTarget?.listen == .live,
                transmitting: model.transmitting,
                onPress: { model.beginTransmit(settings) },
                onRelease: { model.endTransmit() }
            )
        }
    }
}

struct TalkBar: View {
    let title: String? // TX destination display name
    let tag: String? // "TG 3100" or "NODE 55553"
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
                Text(title ?? "No TX target")
                    .font(CW.sans(14, .semibold))
                    .foregroundStyle(title != nil ? CW.white : CW.dim)
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
                            if armed, !transmitting {
                                onPress()
                            }
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
        guard let tag else { return "SELECT IN TALKGROUPS" }
        if transmitting {
            return "TRANSMITTING · \(tag)"
        }
        return armed ? "TX TARGET · \(tag)" : "TX DISARMED · \(tag)"
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
                    Tag(tgName ?? entry.channel ?? "TG \(entry.dst)", color: muted ? CW.amber : CW.blue)
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

/// QRZ credentials for map geocoding, split out to keep SettingsView readable
private struct QRZSection: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        Section {
            TextField("QRZ username", text: settings.$qrzUser)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(CW.mono(14))
                .onChange(of: settings.qrzUser) { model.applyQRZ(settings) }
            SecureField("QRZ password", text: settings.$qrzPassword)
                .onChange(of: settings.qrzPassword) { model.applyQRZ(settings) }
        } header: {
            SectionLabel("QRZ")
        } footer: {
            Text("Used to place stations on the map. A QRZ subscription is required for coordinates.")
                .font(CW.mono(11))
                .foregroundStyle(CW.dim)
        }
    }
}

/// Per-mode station credentials, split out to keep SettingsView readable
private struct StationSection: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Section {
            if settings.netMode == "allstar" {
                TextField("My node number", text: settings.$aslMyNode)
                    .keyboardType(.numberPad)
                    .font(CW.mono(14))
                SecureField("Node password", text: settings.$aslPassword)
                TextField("Callsign", text: settings.$callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(CW.mono(14))
            } else if settings.netMode == "dstar" {
                TextField("Callsign", text: settings.$callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(CW.mono(14))
            } else {
                TextField("DMR ID", text: settings.$dmrID)
                    .keyboardType(.numberPad)
                    .font(CW.mono(14))
                SecureField("Hotspot password", text: settings.$password)
            }
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
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scout = MasterScout()
    @StateObject private var pinger = ICMPPinger()

    /// The Master row shows the selection by directory name when the host is
    /// a known BrandMeister master, or the raw host otherwise.
    private var serverLabel: String {
        guard let selected = BMDirectory.master(forHost: settings.host) else {
            return settings.host
        }
        return "\(selected.id) \(selected.country)"
    }

    private var serverProbe: ProbeState? {
        if let selected = BMDirectory.master(forHost: settings.host) {
            return scout.results[selected.id]
        }
        return scout.results[MasterScout.customKey]
    }

    private var allstarLabel: String {
        let target = settings.aslTarget.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return "Choose a node" }
        if let node = ASLDirectory.shared.node(forNumber: target) {
            return "\(target) · \(node.callsign)"
        }
        return "Node \(target)"
    }

    private var reflectorLabel: String {
        let host = settings.dstarHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return "Choose a reflector" }
        if let reflector = XLXDirectory.reflector(forHost: host) {
            return "\(reflector.name) · \(reflector.country)"
        }
        return host
    }

    /// Directory reflectors carry a baked IP; a custom host only gets a
    /// badge when it's already a literal IPv4 address (no DNS here)
    private var selectedReflectorIP: String? {
        let host = settings.dstarHost.trimmingCharacters(in: .whitespaces)
        if let reflector = XLXDirectory.reflector(forHost: host) {
            return reflector.ipAddress
        }
        var probe = in_addr()
        return inet_pton(AF_INET, host, &probe) == 1 ? host : nil
    }

    private func probeSelected() {
        if settings.netMode == "dstar" {
            if let address = selectedReflectorIP {
                pinger.ping([address])
            }
            return
        }
        guard settings.netMode == "openterminal" else { return }
        let dmrID = UInt32(settings.dmrID.trimmingCharacters(in: .whitespaces)) ?? 0
        if let selected = BMDirectory.master(forHost: settings.host) {
            scout.probeOne(selected, dmrID: dmrID)
        } else if !settings.host.isEmpty, let port = UInt16(exactly: settings.otpPort) {
            scout.probeCustom(host: settings.host.trimmingCharacters(in: .whitespaces),
                              port: port, dmrID: dmrID)
        }
    }

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
                    NavigationLink("Setup guide") { SetupGuideView() }
                } footer: {
                    Text("How to get a DMR ID and password, and what goes where.")
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                }
                Section {
                    Picker("Protocol", selection: settings.$netMode) {
                        Text("Open Terminal (BM)").tag("openterminal")
                        Text("Homebrew (hotspot)").tag("homebrew")
                        Text("D-STAR (XLX)").tag("dstar")
                        Text("AllStar").tag("allstar")
                    }
                    if settings.netMode == "homebrew" {
                        TextField("Host", text: settings.$host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(CW.mono(14))
                        TextField("Port", value: settings.$port, format: .number)
                            .keyboardType(.numberPad)
                            .font(CW.mono(14))
                    } else if settings.netMode == "allstar" {
                        NavigationLink {
                            NodePickerView()
                        } label: {
                            HStack(spacing: 10) {
                                Text(allstarLabel)
                                    .font(CW.mono(14))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                    } else if settings.netMode == "dstar" {
                        NavigationLink {
                            ReflectorPickerView()
                        } label: {
                            HStack(spacing: 10) {
                                Text(reflectorLabel)
                                    .font(CW.mono(14))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if let address = selectedReflectorIP {
                                    LatencyBadge(state: pinger.results[address])
                                }
                            }
                        }
                        TextField("Module", text: settings.$dstarModule)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(CW.mono(14))
                    } else {
                        NavigationLink {
                            MasterPickerView()
                        } label: {
                            HStack(spacing: 10) {
                                Text(serverLabel)
                                    .font(CW.mono(14))
                                    .lineLimit(1)
                                if settings.autoMaster {
                                    Text("auto")
                                        .font(CW.mono(11))
                                        .foregroundStyle(CW.dim)
                                }
                                Spacer()
                                LatencyBadge(state: serverProbe)
                            }
                        }
                    }
                } header: {
                    SectionLabel("Master")
                } footer: {
                    if settings.netMode == "allstar" {
                        Text("The AllStar node to link to. Addresses come from "
                            + "AllStarLink's DNS at connect time.")
                            .font(CW.mono(11))
                            .foregroundStyle(CW.dim)
                    } else if settings.netMode == "dstar" {
                        Text("An XLX or XRF reflector, DExtra port 30001. "
                            + "Module is the letter to link.")
                            .font(CW.mono(11))
                            .foregroundStyle(CW.dim)
                    } else if settings.netMode != "homebrew" {
                        Text(settings.autoMaster
                            ? "Connect pings every BrandMeister master and uses the fastest."
                            : "Pings every BrandMeister master and lets you pick the closest.")
                            .font(CW.mono(11))
                            .foregroundStyle(CW.dim)
                    }
                }
                StationSection()
                Section {
                    NavigationLink("Callsign notes") { CallNotesView() }
                    NavigationLink("Nets") { NetsView() }
                } header: {
                    SectionLabel("Data")
                }
                QRZSection()
                BuddySettingsSection()
                TxMonitorSection()
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
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice decoding by mbelib (ISC license).")
                        Text("Voice encoding by the OP25 project's software AMBE+2 encoder, © Max H. Parke KA1RBI, GPL v3.")
                        Text("Fonts: Outfit and IBM Plex Mono (SIL Open Font License).")
                        Text("Full license texts ship in the source repository under Packages/AMBE.")
                    }
                    .font(CW.sans(13))
                    .foregroundStyle(CW.text)
                    .padding(.vertical, 2)
                } header: {
                    SectionLabel("Acknowledgements")
                }
            }
            .cwList()
            .onAppear {
                probeSelected()
                if settings.netMode == "allstar" {
                    ASLDirectory.shared.loadIfNeeded()
                }
            }
            .onChange(of: settings.host) { _, _ in probeSelected() }
            .onChange(of: settings.otpPort) { _, _ in probeSelected() }
            .onChange(of: settings.dstarHost) { _, _ in probeSelected() }
            .onChange(of: settings.netMode) { _, _ in probeSelected() }
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
