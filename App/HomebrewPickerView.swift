import SwiftUI

// MARK: - HomebrewPickerView

// `autoMaster` is named for the Destination field it drives, which takes its
// name from BrandMeister's own term for a server (see MasterScout).
// swiftlint:disable inclusive_language

/// Picker over the Homebrew (MMDVM) master directory, the counterpart to
/// `MasterPickerView` on the BrandMeister side. Pick a network and the
/// nearest of its servers is chosen at connect; pick a server to pin it.
///
/// Only the selected network's servers are probed. The directory runs to
/// several hundred masters and a blanket sweep would open a socket per
/// entry for a list the user is only skimming.
struct HomebrewPickerView: View {
    // MARK: Internal

    @Binding var host: String
    @Binding var port: Int
    @Binding var autoMaster: Bool
    @Binding var network: String
    @Binding var networkPassword: String

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    HomebrewNetworkPickerView(selected: network) { picked in
                        select(network: picked)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("Network")
                            .font(CW.sans(15))
                        Spacer()
                        Text(network.isEmpty ? "None" : network)
                            .font(CW.sans(15))
                            .foregroundStyle(network.isEmpty ? CW.dim : CW.blue)
                    }
                }
                if !network.isEmpty {
                    Toggle("Automatic", isOn: $autoMaster)
                }
            } header: {
                SectionLabel("Network")
            } footer: {
                FooterNote(network.isEmpty
                    ? "Pick a network — TGIF, AmComm, FreeDMR, DMR+ and the HBLink systems are listed."
                    : "Connect probes every \(network) server and uses the fastest. "
                    + "Picking one below switches to manual.")
            }
            if !servers.isEmpty {
                serverSection
            }
            customSection
        }
        .cwList()
        .navigationTitle("Find a server")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            directory.loadIfNeeded()
            if directory.host(matching: host, port: UInt16(clamping: port)) == nil, !host.isEmpty {
                customHost = host
                customPort = port
            }
            probeSelectedNetwork()
        }
        .onChange(of: network) { _, _ in probeSelectedNetwork() }
        .onDisappear { scout.cancelAll() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scout = HomebrewScout()
    @ObservedObject private var directory = DMRHostsDirectory.shared
    @State private var customHost = ""
    @State private var customPort = 62_031

    private var servers: [DMRHost] {
        network.isEmpty ? [] : directory.hosts(network: network)
    }

    private var trimmedCustomHost: String {
        customHost.trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder private var serverSection: some View {
        if let fastestID = scout.fastest,
           let fastest = servers.first(where: { $0.id == fastestID })
        {
            Section {
                row(fastest)
            } header: {
                SectionLabel("Nearest")
            }
        }
        Section {
            ForEach(servers) { server in
                row(server)
            }
        } header: {
            SectionLabel(network)
        } footer: {
            if servers.contains(where: \.needsOwnPassword) {
                FooterNote("Servers marked KEY want a password of your own, from that network's "
                    + "own signup. The rest use a password published with the server list.")
            }
        }
    }

    private var customSection: some View {
        Section {
            TextField("Host", text: $customHost)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(CW.mono(14))
            // .grouping(.never): a port is an identifier, not a quantity — the
            // default locale formatter renders 62031 as "62,031".
            TextField("Port", value: $customPort, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .font(CW.mono(14))
            Button {
                host = trimmedCustomHost
                port = customPort
                autoMaster = false
                network = ""
                // A hand-typed server is not in the directory, so there is no
                // published password to carry — fall back to the operator's.
                networkPassword = ""
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Text("Use this server")
                        .font(CW.sans(15))
                    if host == trimmedCustomHost, !trimmedCustomHost.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CW.green)
                    }
                }
            }
            .disabled(trimmedCustomHost.isEmpty || customPort <= 0 || customPort > 65_535)
        } header: {
            SectionLabel("Custom")
        } footer: {
            FooterNote("Any master speaking the MMDVM dialect. Most listen on 62031; "
                + "DMR+ and some HBLink systems use their own ports.")
        }
    }

    private func row(_ server: DMRHost) -> some View {
        Button {
            host = server.host
            port = Int(server.port)
            networkPassword = server.needsOwnPassword ? "" : server.password
            autoMaster = false
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(server.label)
                    .font(CW.sans(15))
                    .foregroundStyle(CW.text)
                    .lineLimit(1)
                if server.needsOwnPassword {
                    Text("KEY")
                        .font(CW.mono(10, medium: true))
                        .foregroundStyle(CW.amber)
                }
                if host == server.host, port == Int(server.port) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CW.green)
                }
                Spacer()
                LatencyBadge(state: scout.results[server.id])
            }
        }
    }

    private func select(network picked: String) {
        network = picked
        autoMaster = true
        // Clear the pinned server so the probe picks one for the new network.
        host = ""
        networkPassword = ""
    }

    private func probeSelectedNetwork() {
        let targets = servers
        guard !targets.isEmpty else {
            scout.cancelAll()
            return
        }
        scout.probeAll(targets)
    }
}

// MARK: - HomebrewNetworkPickerView

/// Searchable list of the networks in the host file, with how many servers
/// each one lists.
struct HomebrewNetworkPickerView: View {
    // MARK: Internal

    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        List {
            ForEach(matches, id: \.self) { name in
                Button {
                    onPick(name)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text(name)
                            .font(CW.sans(15))
                            .foregroundStyle(CW.text)
                        if name == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CW.green)
                        }
                        Spacer()
                        Text("\(directory.hosts(network: name).count)")
                            .font(CW.mono(12))
                            .foregroundStyle(CW.xdim)
                    }
                }
            }
        }
        .cwList()
        .searchable(text: $query, prompt: "Network")
        .navigationTitle("Networks")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { directory.loadIfNeeded() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var directory = DMRHostsDirectory.shared
    @State private var query = ""

    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return directory.networks
        }
        // Match the network name or any of its servers, so searching for a
        // city or a callsign finds the network holding it.
        return directory.networks.filter { name in
            name.localizedCaseInsensitiveContains(trimmed)
                || directory.hosts(network: name).contains {
                    $0.label.localizedCaseInsensitiveContains(trimmed)
                }
        }
    }
}

// swiftlint:enable inclusive_language
