import SwiftUI
import UniformTypeIdentifiers

/// Full nets list: add/edit/delete, enable toggles, share/import, and the
/// reminder budget footer (iOS keeps only the 64 soonest requests).
struct NetsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: MonitorModel
    @State private var scheduled = 0
    @State private var trimmed = 0
    @State private var importing = false
    @State private var importResult: String?
    @State private var permissionDenied = false

    var body: some View {
        Form {
            Section {
                ForEach(settings.netList) { net in
                    row(net)
                }
                .onDelete { offsets in
                    var list = settings.netList
                    list.remove(atOffsets: offsets)
                    settings.netList = list
                    refreshSchedule()
                }
                Button {
                    var list = settings.netList
                    list.append(Net())
                    settings.netList = list
                } label: {
                    Label("Add net", systemImage: "plus")
                        .font(CW.sans(15))
                }
            } header: {
                SectionLabel("Nets")
            } footer: {
                Text(footerText)
                    .font(CW.mono(11))
                    .foregroundStyle(trimmed > 0 ? CW.amber : CW.dim)
            }
            if permissionDenied {
                Section {
                    Button("Notifications are off — open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundStyle(CW.amber)
                }
            }
            Section {
                Button {
                    fetchDirectory()
                } label: {
                    Label("Fetch net directory", systemImage: "arrow.down.circle")
                        .font(CW.sans(15))
                }
                ShareLink(
                    item: NetsExport(nets: settings.netList),
                    preview: SharePreview("DMR nets")
                ) {
                    Label("Share net list", systemImage: "square.and.arrow.up")
                        .font(CW.sans(15))
                }
                .disabled(settings.netList.isEmpty)
                Button {
                    importing = true
                } label: {
                    Label("Import nets", systemImage: "square.and.arrow.down")
                        .font(CW.sans(15))
                }
                if let importResult {
                    Text(importResult)
                        .font(CW.mono(12))
                        .foregroundStyle(CW.green)
                }
            } header: {
                SectionLabel("Sharing")
            } footer: {
                Text("The directory imports nets disabled; switch on the ones you want reminders for.")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
        }
        .cwList()
        .navigationTitle("Nets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json])
        { result in
            importNets(result)
        }
        .task {
            permissionDenied = !(await PushManager.shared.requestAuthorization())
            refreshSchedule()
        }
        .onDisappear { refreshSchedule() }
    }

    private func row(_ net: Net) -> some View {
        NavigationLink {
            NetEditView(netID: net.id)
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { net.enabled },
                    set: { enabled in
                        var list = settings.netList
                        if let index = list.firstIndex(where: { $0.id == net.id }) {
                            list[index].enabled = enabled
                            settings.netList = list
                        }
                        refreshSchedule()
                    }
                ))
                .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(net.name.isEmpty ? "TG \(String(net.talkgroup))" : net.name)
                        .font(CW.sans(15, .medium))
                    Text("TG \(String(net.talkgroup)) · \(net.wallTime) \(shortZone(net))")
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                }
                Spacer()
                if let next = NetSchedule.nextOccurrence(of: net, after: Date()),
                   net.enabled
                {
                    Text(NetSchedule.countdown(to: next, from: Date()))
                        .font(CW.mono(11))
                        .foregroundStyle(CW.blue)
                }
            }
        }
    }

    private func shortZone(_ net: Net) -> String {
        net.timeZone.abbreviation() ?? net.timeZoneID
    }

    private var footerText: String {
        var text = "\(scheduled) / \(NetScheduler.maxRequests) reminders scheduled."
        if trimmed > 0 {
            text += " \(trimmed) trimmed — too many nets × reminders."
        }
        return text
    }

    private func refreshSchedule() {
        Task {
            let result = await NetScheduler.reschedule(
                settings.netList, tgName: settings.tgName
            )
            scheduled = result.0
            trimmed = result.1
        }
    }

    /// Community net directory (scraped from dvnets.com, see the
    /// dmr-lookout repo); an update is a re-fetch — merge is by net id
    private static let directoryURL = URL(
        string: "https://raw.githubusercontent.com/jsvana/dmr-lookout/main/nets/dmr-nets.json"
    )!

    private func fetchDirectory() {
        importResult = "fetching…"
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: Self.directoryURL)
                merge(data)
            } catch {
                importResult = error.localizedDescription
            }
        }
    }

    private func importNets(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            importResult = "couldn't read file"
            return
        }
        merge(data)
    }

    private func merge(_ data: Data) {
        let decoder = JSONDecoder()
        let incoming: [Net]
        if let file = try? decoder.decode(NetsFile.self, from: data) {
            incoming = file.nets
        } else if let bare = try? decoder.decode([Net].self, from: data) {
            incoming = bare
        } else {
            importResult = "not a nets file"
            return
        }
        var list = settings.netList
        var updated = 0
        var added = 0
        for net in incoming where net.talkgroup > 0 {
            if let index = list.firstIndex(where: { $0.id == net.id }) {
                // Schedule/TG updates land, but the user's own choices
                // (enabled, reminder leads) survive a re-fetch
                var merged = net
                merged.enabled = list[index].enabled
                merged.leads = list[index].leads
                list[index] = merged
                updated += 1
            } else {
                list.append(net)
                added += 1
            }
        }
        settings.netList = list
        importResult = "Imported \(added + updated) nets"
            + (updated > 0 ? " (\(updated) updated)" : "")
        refreshSchedule()
    }
}

/// JSON export via the share sheet, no temp files
struct NetsExport: Transferable {
    let nets: [Net]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try JSONEncoder().encode(NetsFile(version: 1, nets: export.nets))
        }
        .suggestedFileName("dmr-nets.json")
    }
}
