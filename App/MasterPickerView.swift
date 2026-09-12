import SwiftUI

// "Master" is BrandMeister's own name for its servers (see MasterScout).
// swiftlint:disable inclusive_language

/// Picker over the BrandMeister master directory. Every master is probed on
/// appear; rows show live round-trip time and tapping one sets the host.
struct MasterPickerView: View {
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scout = MasterScout()
    @State private var customHost = ""
    @State private var customPort = Int(MasterScout.openTerminalPort)

    private var trimmedCustomHost: String {
        customHost.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Automatic", isOn: settings.$autoMaster)
            } footer: {
                Text("Connect probes every master and uses the fastest. Picking one below switches to manual.")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
            if let fastestID = scout.fastest,
               let fastest = BMDirectory.all.first(where: { $0.id == fastestID })
            {
                Section {
                    row(fastest)
                } header: {
                    SectionLabel("Nearest")
                }
            }
            ForEach(BMDirectory.regions, id: \.name) { region in
                Section {
                    ForEach(region.masters) { master in
                        row(master)
                    }
                } header: {
                    SectionLabel(region.name)
                }
            }
            Section {
                TextField("Host", text: $customHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(CW.mono(14))
                TextField("Port", value: $customPort, format: .number)
                    .keyboardType(.numberPad)
                    .font(CW.mono(14))
                Button {
                    settings.host = trimmedCustomHost
                    settings.otpPort = customPort
                    settings.autoMaster = false
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text("Use this server")
                            .font(CW.sans(15))
                        if settings.host == trimmedCustomHost, !trimmedCustomHost.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CW.green)
                        }
                    }
                }
                .disabled(trimmedCustomHost.isEmpty || customPort <= 0 || customPort > 65535)
            } header: {
                SectionLabel("Custom")
            } footer: {
                Text("Any Open Terminal server. BrandMeister masters use port 54006.")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
        }
        .cwList()
        .navigationTitle("Find a master")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            // Pre-fill the custom fields when the selection is already custom
            if BMDirectory.master(forHost: settings.host) == nil, !settings.host.isEmpty {
                customHost = settings.host
                customPort = settings.otpPort
            }
            let dmrID = UInt32(settings.dmrID.trimmingCharacters(in: .whitespaces)) ?? 0
            scout.probeAll(dmrID: dmrID) { fastest in
                // Mirror what connect will do so the checkmark shows it
                if settings.autoMaster, let (master, _) = fastest {
                    settings.host = master.host
                    settings.otpPort = Int(MasterScout.openTerminalPort)
                }
            }
        }
        .onDisappear { scout.cancelAll() }
    }

    private func row(_ master: BMMaster) -> some View {
        Button {
            settings.host = master.host
            settings.otpPort = Int(MasterScout.openTerminalPort)
            settings.autoMaster = false
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(String(master.id))
                    .font(CW.mono(14, medium: true))
                    .foregroundStyle(CW.blue)
                Text(master.country)
                    .font(CW.sans(15))
                    .foregroundStyle(CW.text)
                if settings.host == master.host {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CW.green)
                }
                Spacer()
                LatencyBadge(state: scout.results[master.id])
            }
        }
    }
}

/// Round-trip time chip shared by the picker rows and the Settings row.
struct LatencyBadge: View {
    let state: ProbeState?

    var body: some View {
        switch state {
        case nil, .probing?:
            Text("· · ·")
                .font(CW.mono(12))
                .foregroundStyle(CW.xdim)
        case let .reachable(millis)?:
            Text("\(millis) ms")
                .font(CW.mono(12))
                .foregroundStyle(millis <= 100 ? CW.green : CW.amber)
        case .unreachable?:
            Text("—")
                .font(CW.mono(12))
                .foregroundStyle(CW.dim)
        }
    }
}

// swiftlint:enable inclusive_language
