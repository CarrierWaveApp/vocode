import SwiftUI

// MARK: - DestinationSwitcherView

/// Sheet behind the nav-bar title: connection status plus the saved
/// destination list. Tapping a destination activates it and connects;
/// destinations are added and edited here too.
struct DestinationSwitcherView: View {
    // MARK: Internal

    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel

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
                    ForEach(settings.destinations) { dest in
                        row(dest)
                    }
                    .onDelete { offsets in
                        let list = settings.destinations
                        for i in offsets {
                            settings.delete(list[i])
                        }
                    }
                } header: {
                    SectionLabel("Destinations")
                } footer: {
                    FooterNote("Tap to switch and connect. Swipe for edit and delete.")
                }
            }
            .cwList()
            .navigationTitle("Destinations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(DestinationKind.allCases) { kind in
                            Button(kind.label) {
                                editing = Destination(kind: kind)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $editing) { dest in
                DestinationEditView(draft: dest)
            }
            .onAppear {
                // Refresh the saved copy of the active destination so rows
                // and edits reflect changes made while it was active
                settings.snapshotActiveDestination()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var editing: Destination?

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isConnected ? CW.green : CW.xdim)
                .frame(width: 8, height: 8)
            Text(model.isConnected ? settings.connectedSummary : model.link.label)
                .font(CW.sans(15, .medium))
                .foregroundStyle(model.isConnected ? CW.white : CW.text)
                .lineLimit(1)
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

    private func row(_ dest: Destination) -> some View {
        let isActive = dest.id.uuidString == settings.activeDestinationID
        return Button {
            settings.activate(dest)
            model.connect(settings)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dest.displayName)
                        .font(CW.sans(15, .medium))
                        .foregroundStyle(CW.white)
                    Text(dest.summary)
                        .font(CW.sans(12))
                        .foregroundStyle(CW.dim)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CW.green)
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                settings.delete(dest)
            }
            Button("Edit") {
                settings.snapshotActiveDestination()
                editing = settings.destinations.first { $0.id == dest.id } ?? dest
            }
            .tint(CW.blue)
        }
    }
}

// MARK: - DestinationEditView

/// Add/edit form for one destination. Works on a draft; Save stores it
/// and, when it's the active destination, refreshes the working keys.
struct DestinationEditView: View {
    // MARK: Internal

    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel
    @State var draft: Destination

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $draft.name)
            } footer: {
                FooterNote("Shown in the destination list; leave blank for an automatic label.")
            }
            kindSection
            if draft.kind.isDMR {
                talkgroupSection
            }
        }
        .cwList()
        .navigationTitle(isNew ? "Add destination" : "Edit destination")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    settings.applyEdits(draft)
                    if draft.id.uuidString == settings.activeDestinationID {
                        model.applyListenStates(settings)
                    }
                    dismiss()
                }
                .disabled(!valid)
            }
        }
        .onAppear {
            if draft.kind == .allstar {
                ASLDirectory.shared.loadIfNeeded()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool {
        !settings.destinations.contains { $0.id == draft.id }
    }

    private var valid: Bool {
        switch draft.kind {
        case .brandmeister:
            draft.autoMaster || !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
        case .hotspot:
            !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
                && draft.port > 0 && draft.port < 65_536
        case .dstar:
            !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
                && !draft.module.trimmingCharacters(in: .whitespaces).isEmpty
        case .allstar:
            !draft.node.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var serverLabel: String {
        guard let selected = BMDirectory.master(forHost: draft.host) else {
            return draft.host.isEmpty ? "Choose a master" : draft.host
        }
        return "\(selected.id) \(selected.country)"
    }

    private var reflectorLabel: String {
        let host = draft.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            return "Choose a reflector"
        }
        if let reflector = XLXDirectory.reflector(forHost: host) {
            return "\(reflector.name) · \(reflector.country)"
        }
        return host
    }

    private var nodeLabel: String {
        let target = draft.node.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            return "Choose a node"
        }
        if let node = ASLDirectory.shared.node(forNumber: target) {
            return "\(target) · \(node.callsign)"
        }
        return "Node \(target)"
    }

    @ViewBuilder private var kindSection: some View {
        switch draft.kind {
        case .brandmeister:
            Section {
                NavigationLink {
                    MasterPickerView(host: $draft.host, otpPort: $draft.otpPort,
                                     autoMaster: $draft.autoMaster)
                } label: {
                    HStack(spacing: 10) {
                        Text(serverLabel)
                            .font(CW.mono(14))
                            .lineLimit(1)
                        if draft.autoMaster {
                            Text("auto")
                                .font(CW.mono(11))
                                .foregroundStyle(CW.dim)
                        }
                        Spacer()
                    }
                }
            } header: {
                SectionLabel("Server")
            } footer: {
                FooterNote(draft.autoMaster
                    ? "Connect pings every BrandMeister master and uses the fastest."
                    : "Connects to the selected BrandMeister master.")
            }
        case .hotspot:
            Section {
                TextField("Host", text: $draft.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(CW.mono(14))
                TextField("Port", value: $draft.port, format: .number)
                    .keyboardType(.numberPad)
                    .font(CW.mono(14))
            } header: {
                SectionLabel("Hotspot")
            } footer: {
                FooterNote("Your hotspot or repeater's Homebrew address. "
                    + "Uses the DMR ID, password, suffix, and location from Settings.")
            }
        case .dstar:
            Section {
                NavigationLink {
                    ReflectorPickerView(host: $draft.host)
                } label: {
                    HStack(spacing: 10) {
                        Text(reflectorLabel)
                            .font(CW.mono(14))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
                TextField("Module", text: $draft.module)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(CW.mono(14))
            } header: {
                SectionLabel("Reflector")
            } footer: {
                FooterNote("An XLX or XRF reflector, DExtra port 30001. "
                    + "Module is the letter to link.")
            }
        case .allstar:
            Section {
                NavigationLink {
                    NodePickerView(node: $draft.node)
                } label: {
                    HStack(spacing: 10) {
                        Text(nodeLabel)
                            .font(CW.mono(14))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
            } header: {
                SectionLabel("Node")
            } footer: {
                FooterNote("The AllStar node to link to. Addresses come from "
                    + "AllStarLink's DNS at connect time. Uses your node "
                    + "credentials from Settings.")
            }
        }
    }

    private var talkgroupSection: some View {
        Section {
            ForEach($draft.talkgroups) { $tg in
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
            .onDelete { draft.talkgroups.remove(atOffsets: $0) }
            Button {
                draft.talkgroups.append(Talkgroup(tg: 0, name: ""))
            } label: {
                Label("Add talkgroup", systemImage: "plus")
                    .font(CW.sans(15))
            }
        } header: {
            SectionLabel("Talkgroups")
        } footer: {
            FooterNote("Applied on next connect. Swipe to delete.")
        }
    }
}
