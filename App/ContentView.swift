import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings
    @State private var showSettings = false

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
                    if model.heard.isEmpty {
                        Text("Nothing heard yet")
                            .foregroundStyle(CW.dim)
                    }
                    ForEach(model.heard) { entry in
                        HeardRow(entry: entry, muted: model.muted.contains(entry.dst))
                            .swipeActions {
                                Button(model.muted.contains(entry.dst) ? "Unmute TG" : "Mute TG") {
                                    model.toggleMute(entry.dst)
                                }
                                .tint(CW.amber)
                            }
                    }
                } header: {
                    SectionLabel("Last heard")
                }
            }
            .cwList()
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
            if !settings.options.isEmpty {
                Text(settings.options)
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
        }
        .padding(.vertical, 4)
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
                    Tag("TG \(entry.dst)", color: muted ? CW.amber : CW.blue)
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
    @Environment(\.dismiss) private var dismiss

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
                    TextField("Options", text: settings.$options)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(CW.mono(14))
                } header: {
                    SectionLabel("Static talkgroups")
                } footer: {
                    Text(settings.netMode == "homebrew"
                        ? "Format: TS2_1=91;TS2_2=3100"
                        : "Format: 91;3100")
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
