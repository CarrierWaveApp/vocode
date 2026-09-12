import SwiftUI

/// The Buddy watch block in SettingsView's Form
struct BuddySettingsSection: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var buddyClient: BuddyClient

    var body: some View {
        Section {
            Toggle("Buddy watch", isOn: settings.$buddyWatchEnabled)
                .onChange(of: settings.buddyWatchEnabled) { _, enabled in
                    if enabled {
                        buddyClient.startup(settings)
                    } else {
                        buddyClient.deregister(settings)
                    }
                }
            if settings.buddyWatchEnabled {
                NavigationLink("Buddies (\(settings.buddyList.count))") {
                    BuddyListView()
                }
                TextField("Server URL", text: settings.$buddyServerURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(CW.mono(14))
                    .onChange(of: settings.buddyServerURL) {
                        buddyClient.startup(settings)
                    }
                // Credentials entered after the toggle must still register:
                // the token-arrival path bails while they're missing
                SecureField("API token", text: settings.$buddyAPIToken)
                    .onChange(of: settings.buddyAPIToken) {
                        buddyClient.startup(settings)
                    }
            }
        } header: {
            SectionLabel("Buddy watch")
        } footer: {
            Text("Push notifications when a watched callsign keys up anywhere on BrandMeister.")
                .font(CW.mono(11))
                .foregroundStyle(CW.dim)
        }
    }
}

/// Buddy watch list editor; mirrors the Talkgroups editing block in Settings
struct BuddyListView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var buddyClient: BuddyClient

    var body: some View {
        Form {
            Section {
                ForEach(list) { $buddy in
                    HStack(spacing: 12) {
                        TextField("Call", text: $buddy.callsign)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(CW.mono(14))
                            .frame(width: 90)
                            .onChange(of: buddy.callsign) {
                                resolveID(buddy.id)
                            }
                        TextField("Name", text: $buddy.label)
                        if buddy.dmrID > 0 {
                            Text(String(buddy.dmrID))
                                .font(CW.mono(11))
                                .foregroundStyle(CW.dim)
                        }
                    }
                }
                .onDelete { list.wrappedValue.remove(atOffsets: $0) }
                Button {
                    list.wrappedValue.append(Buddy())
                } label: {
                    Label("Add buddy", systemImage: "plus")
                        .font(CW.sans(15))
                }
            } header: {
                SectionLabel("Buddies")
            } footer: {
                Text("Pushed when a buddy keys up anywhere on BrandMeister. Swipe to delete.")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
            Section {
                statusRow
                Button("Send test notification") {
                    testResult = "…"
                    Task { testResult = await buddyClient.sendTest(settings) ?? "sent" }
                }
                .disabled(!settings.buddyConfigured)
                if let testResult {
                    Text(testResult)
                        .font(CW.mono(12))
                        .foregroundStyle(testResult == "sent" ? CW.green : CW.amber)
                }
            } header: {
                SectionLabel("Status")
            }
        }
        .cwList()
        .navigationTitle("Buddy watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onDisappear { buddyClient.syncIfNeeded(settings) }
    }

    @State private var testResult: String?

    private var list: Binding<[Buddy]> {
        Binding(
            get: { settings.buddyList },
            set: { settings.buddyList = $0 }
        )
    }

    private var statusRow: some View {
        HStack {
            Text("Sync")
            Spacer()
            Text(statusText)
                .font(CW.mono(12))
                .foregroundStyle(statusColor)
        }
    }

    private var statusText: String {
        switch buddyClient.status {
        case .idle: return "idle"
        case .syncing: return "syncing"
        case let .synced(when):
            return "synced \(when.formatted(date: .omitted, time: .shortened))"
        case let .failed(why): return why
        }
    }

    private var statusColor: Color {
        switch buddyClient.status {
        case .synced: return CW.green
        case .failed: return CW.red
        default: return CW.dim
        }
    }

    /// Fill in the DMR ID once a callsign stops changing; best-effort
    private func resolveID(_ buddyID: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            var current = settings.buddyList
            guard let index = current.firstIndex(where: { $0.id == buddyID }) else { return }
            let call = current[index].callsign
            guard call.count >= 3,
                  let dmrID = await BuddyClient.dmrID(forCallsign: call),
                  let again = settings.buddyList.firstIndex(where: { $0.id == buddyID }),
                  settings.buddyList[again].callsign == call
            else { return }
            current = settings.buddyList
            current[again].dmrID = dmrID
            settings.buddyList = current
        }
    }
}
