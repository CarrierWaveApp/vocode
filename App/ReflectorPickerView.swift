import SwiftUI

/// Searchable picker over the bundled XLX reflector snapshot, grouped by
/// country. Tapping a reflector sets the bound host; a Custom section
/// keeps free-text entry for anything not in the snapshot.
struct ReflectorPickerView: View {
    // MARK: Internal

    @Binding var host: String

    var body: some View {
        Form {
            ForEach(byCountry, id: \.country) { group in
                Section {
                    ForEach(group.reflectors) { reflector in
                        row(reflector)
                    }
                } header: {
                    SectionLabel(group.country)
                }
            }
            Section {
                TextField("Host", text: $customHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(CW.mono(14))
                Button {
                    host = trimmedCustomHost
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text("Use this host")
                            .font(CW.sans(15))
                        if host == trimmedCustomHost, !trimmedCustomHost.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CW.green)
                        }
                    }
                }
                .disabled(trimmedCustomHost.isEmpty)
            } header: {
                SectionLabel("Custom")
            }
        }
        .cwList()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Reflectors")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            if XLXDirectory.reflector(forHost: host) == nil {
                customHost = host
            }
            pinger.ping(XLXDirectory.all.map(\.ipAddress))
        }
        .onDisappear { pinger.cancel() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @StateObject private var pinger = ICMPPinger()
    @State private var search = ""
    @State private var customHost = ""

    private var trimmedCustomHost: String {
        customHost.trimmingCharacters(in: .whitespaces)
    }

    private var filtered: [XLXReflector] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return XLXDirectory.all
        }
        return XLXDirectory.all.filter {
            $0.name.lowercased().contains(needle)
                || $0.host.lowercased().contains(needle)
                || $0.country.lowercased().contains(needle)
        }
    }

    private var byCountry: [(country: String, reflectors: [XLXReflector])] {
        Dictionary(grouping: filtered, by: \.country)
            .map { (country: $0.key, reflectors: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.country < $1.country }
    }

    private func row(_ reflector: XLXReflector) -> some View {
        Button {
            host = reflector.host
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(reflector.name)
                    .font(CW.mono(14, medium: true))
                    .foregroundStyle(CW.blue)
                Text(reflector.host)
                    .font(CW.mono(12))
                    .foregroundStyle(CW.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if host == reflector.host {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CW.green)
                }
                Spacer()
                LatencyBadge(state: pinger.results[reflector.ipAddress])
            }
        }
    }
}
