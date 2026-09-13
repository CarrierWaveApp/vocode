// swiftlint:disable file_length

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        NavigationStack {
            List {
                if !model.isConnected || model.audioError != nil {
                    Section {
                        statusRow
                        logLink
                        if let err = model.audioError {
                            Text(err).font(CW.sans(12)).foregroundStyle(CW.red)
                        }
                    }
                }
                if settings.activeKind.isDMR {
                    Section {
                        tgHeader
                        if !tgCollapsed {
                            ForEach(settings.talkgroupList.filter { $0.tg > 0 }) { tg in
                                TGRow(
                                    tg: tg,
                                    isTX: settings.txTargetTG == Int(tg.tg),
                                    setState: { state in
                                        settings.setListen(tg.tg, state)
                                        model.applyListenStates(settings)
                                    },
                                    selectTX: {
                                        guard tg.listen == .live else {
                                            return
                                        }
                                        settings.txTargetTG =
                                            settings.txTargetTG == Int(tg.tg) ? 0 : Int(tg.tg)
                                    }
                                )
                            }
                            Button {
                                settings.snapshotActiveDestination()
                                if let active = settings.activeDestination {
                                    editingDestination = active
                                }
                            } label: {
                                Label("Edit talkgroups", systemImage: "pencil")
                                    .font(CW.sans(14))
                                    .foregroundStyle(CW.dim)
                            }
                            .disabled(settings.activeDestination == nil)
                        }
                    } header: {
                        SectionLabel("Talkgroups")
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
            .sheet(isPresented: $showSwitcher) {
                DestinationSwitcherView()
                    .environmentObject(model)
                    .environmentObject(settings)
            }
            .sheet(item: $editingDestination) { dest in
                NavigationStack {
                    DestinationEditView(draft: dest)
                }
                .preferredColorScheme(.dark)
            }
        }
        .environmentObject(buddyClient)
        .task {
            buddyClient.startup(settings)
            model.refreshHistory(settings)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Private

    @State private var showSettings = false
    @State private var showMap = false
    @State private var showSwitcher = false
    @State private var editingDestination: Destination?
    @StateObject private var buddyClient = BuddyClient()
    @AppStorage("tgCollapsed") private var tgCollapsed = false

    private var headerTitle: String {
        if model.isConnected {
            return settings.connectedSummary
        }
        return settings.activeDestination?.displayName ?? "Choose destination"
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
                HStack(spacing: 10) {
                    countBadge(live, icon: "speaker.wave.2.fill", color: CW.green, label: "live")
                    countBadge(mutedCount, icon: "speaker.slash.fill", color: CW.amber, label: "muted")
                    countBadge(off, icon: "power", color: CW.xdim, label: "off")
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Lives in the nav bar as the principal item: dot, destination,
    /// picker chevrons. Tapping opens the destination switcher.
    private var headerStatus: some View {
        Button {
            showSwitcher = true
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.isConnected ? CW.green : CW.xdim)
                    .frame(width: 8, height: 8)
                Text(headerTitle)
                    .font(CW.sans(14, .medium))
                    .foregroundStyle(model.isConnected ? CW.white : CW.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CW.dim)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Destination: \(headerTitle), \(model.isConnected ? "connected" : "disconnected")")
        .accessibilityHint("Opens the destination switcher")
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

    @ViewBuilder
    private func countBadge(_ n: Int, icon: String, color: Color, label: String) -> some View {
        if n > 0 {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
                Text("\(n)")
                    .font(CW.mono(10))
                    .foregroundStyle(CW.dim)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(n) \(label)")
        }
    }
}

// MARK: - TGRow

struct TGRow: View {
    // MARK: Internal

    let tg: Talkgroup
    let isTX: Bool
    let setState: (ListenState) -> Void
    let selectTX: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Listen state", selection: Binding(
                    get: { tg.listen },
                    set: { setState($0) }
                )) {
                    Label("Live", systemImage: "speaker.wave.2.fill")
                        .tag(ListenState.live)
                    Label("Muted", systemImage: "speaker.slash.fill")
                        .tag(ListenState.muted)
                    Label("Off", systemImage: "power")
                        .tag(ListenState.off)
                }
            } label: {
                Image(systemName: stateIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(stateColor)
                    .frame(width: 38, height: 38)
                    .background(CW.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(tg.listen == .off ? CW.border : stateColor.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Listen state: \(tg.listen.rawValue)")
            VStack(alignment: .leading, spacing: 2) {
                Text(tg.name.isEmpty ? "TG \(tg.tg)" : tg.name)
                    .font(CW.sans(15, .medium))
                    .foregroundStyle(tg.listen == .off ? CW.dim : CW.white)
                // String(tg) keeps Text's localized interpolation from
                // rendering 3100 as "3,100"
                Text("TG \(String(tg.tg)) · \(tg.listen.rawValue)")
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isTX ? "Talk target" : "Set as talk target")
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var stateIcon: String {
        switch tg.listen {
        case .live: "speaker.wave.2.fill"
        case .muted: "speaker.slash.fill"
        case .off: "power"
        }
    }

    private var stateColor: Color {
        switch tg.listen {
        case .live: CW.green
        case .muted: CW.amber
        case .off: CW.xdim
        }
    }
}

// MARK: - TalkBarHost

/// Hosts the talk bar and the expanded talk sheet it opens
struct TalkBarHost: View {
    // MARK: Internal

    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        TalkBar(
            dest: TxDestination(settings),
            transmitting: model.transmitting,
            toggleMode: settings.pttToggle,
            onPress: { model.beginTransmit(settings) },
            onRelease: { model.endTransmit() },
            onExpand: { showTalkSheet = true }
        )
        .sheet(isPresented: $showTalkSheet) {
            TalkSheet()
                .environmentObject(model)
                .environmentObject(settings)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Private

    @State private var showTalkSheet = false
}

// MARK: - TalkBar

struct TalkBar: View {
    // MARK: Internal

    let dest: TxDestination
    let transmitting: Bool
    let toggleMode: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dest.rxOnly ? "speaker.wave.2.fill" : "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(transmitting ? CW.red : (dest.armed ? CW.blue : CW.xdim))
                .symbolEffect(.pulse, isActive: transmitting)
            VStack(alignment: .leading, spacing: 2) {
                Text(dest.title ?? "No talk target")
                    .font(CW.sans(14, .semibold))
                    .foregroundStyle(dest.title != nil ? CW.white : CW.dim)
                Text(dest.status(transmitting: transmitting))
                    .font(CW.sans(11))
                    .foregroundStyle(CW.dim)
            }
            Spacer()
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CW.dim)
            if !dest.rxOnly {
                pttCapsule
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(CW.raised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CW.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        // Tap or swipe up anywhere outside the capsule expands into the
        // talk sheet; the capsule's own gesture wins on the capsule
        .onTapGesture { onExpand() }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height < -20 {
                        onExpand()
                    }
                }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: Private

    @ViewBuilder private var pttCapsule: some View {
        let armed = dest.armed
        let capsule = Text(PTTLabel.text(transmitting: transmitting, toggleMode: toggleMode))
            .font(CW.sans(13, .medium))
            .foregroundStyle(transmitting ? CW.white : (armed ? CW.bg : CW.text))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(transmitting ? CW.red : (armed ? CW.blue : CW.raised))
            .overlay(Capsule().stroke(armed || transmitting ? .clear : CW.border, lineWidth: 1))
            .clipShape(Capsule())
            .opacity(armed || transmitting ? 1 : 0.45)
        if toggleMode {
            capsule.onTapGesture {
                if transmitting {
                    onRelease()
                } else if armed {
                    onPress()
                }
            }
        } else {
            capsule.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if armed, !transmitting {
                            onPress()
                        }
                    }
                    .onEnded { _ in onRelease() }
            )
        }
    }
}

// MARK: - LogView

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

// MARK: - HeardRow

struct HeardRow: View {
    // MARK: Internal

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

    // MARK: Private

    private var duration: String {
        let seconds = Int((entry.ended ?? Date()).timeIntervalSince(entry.started))
        return seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

// MARK: - Tag

struct Tag: View {
    // MARK: Lifecycle

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    // MARK: Internal

    let text: String
    let color: Color

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

// MARK: - QRZSection

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
            FooterNote("Used to place stations on the map. A QRZ subscription is required for coordinates.")
        }
    }
}

// MARK: - StationSection

/// Station identity, split out to keep SettingsView readable. Static —
/// the same fields regardless of the active destination.
private struct StationSection: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Section {
            TextField("Callsign", text: settings.$callsign)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(CW.mono(14))
            TextField("DMR ID", text: settings.$dmrID)
                .keyboardType(.numberPad)
                .font(CW.mono(14))
            SecureField("Hotspot password", text: settings.$password)
            TextField("Hotspot suffix", text: settings.$suffix)
                .keyboardType(.numberPad)
                .font(CW.mono(14))
            TextField("Location", text: settings.$location)
        } header: {
            SectionLabel("Station")
        } footer: {
            FooterNote("Callsign and DMR ID identify you on every network. "
                + "The password comes from BrandMeister SelfCare; suffix and "
                + "location only matter for hotspot destinations.")
        }
        Section {
            TextField("My node number", text: settings.$aslMyNode)
                .keyboardType(.numberPad)
                .font(CW.mono(14))
            SecureField("Node password", text: settings.$aslPassword)
        } header: {
            SectionLabel("AllStar")
        } footer: {
            FooterNote("Your registered AllStar node credentials, used when "
                + "connecting to AllStar destinations.")
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    // MARK: Internal

    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Setup guide") { SetupGuideView() }
                } footer: {
                    FooterNote("How to get a DMR ID and password, and what goes where.")
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
                    FooterNote("Going live on a talkgroup switches the others off. "
                        + "Turn off to monitor several at once. Destinations and "
                        + "their talkgroups live behind the title on the main screen.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice decoding by mbelib (ISC license).")
                        Text(
                            "Voice encoding by the OP25 project's software AMBE+2 encoder, "
                                + "© Max H. Parke KA1RBI, GPL v3."
                        )
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

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
