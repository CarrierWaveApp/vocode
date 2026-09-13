import SwiftUI

/// Per-net editor. Edits write straight into settings.netList; reminders
/// are rebuilt once on the way out, never per keystroke.
struct NetEditView: View {
    // MARK: Internal

    @EnvironmentObject var settings: Settings

    let netID: UUID

    var body: some View {
        Form {
            Section {
                TextField("Net name", text: binding(\.name))
                TextField("Network (label)", text: binding(\.network))
                TextField("Talkgroup", text: Binding(
                    get: { net.talkgroup == 0 ? "" : String(net.talkgroup) },
                    set: { text in
                        update { $0.talkgroup = UInt32(text.filter(\.isNumber)) ?? 0 }
                    }
                ))
                .keyboardType(.numberPad)
                .font(CW.mono(14))
            } header: {
                SectionLabel("Net")
            }
            Section {
                weekdayRow
                DatePicker("Start time", selection: timeBinding,
                           displayedComponents: .hourAndMinute)
                Picker("Time zone", selection: zoneBinding) {
                    ForEach(zoneChoices, id: \.self) { zone in
                        Text(zone).tag(zone)
                    }
                }
                Stepper("Duration: \(net.durationMin) min",
                        value: durationBinding, in: 15 ... 240, step: 15)
            } header: {
                SectionLabel("Schedule")
            } footer: {
                FooterNote("Times are in the net's own time zone; they don't shift when you travel.")
            }
            Section {
                leadToggle(10, "10 minutes before")
                leadToggle(5, "5 minutes before")
                leadToggle(0, "At start")
            } header: {
                SectionLabel("Reminders")
            }
            Section {
                TextField("Notes", text: binding(\.notes), axis: .vertical)
            } header: {
                SectionLabel("Notes")
            }
        }
        .cwList()
        .navigationTitle(net.name.isEmpty ? "New net" : net.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onDisappear {
            Task { await NetScheduler.reschedule(settings.netList, tgName: settings.tgName) }
        }
    }

    // MARK: Private

    private static let zones: [String] = {
        var ids = [
            "UTC", "America/New_York", "America/Chicago", "America/Denver",
            "America/Phoenix", "America/Los_Angeles", "America/Anchorage",
            "Pacific/Honolulu", "Europe/London",
        ]
        if !ids.contains(TimeZone.current.identifier) {
            ids.append(TimeZone.current.identifier)
        }
        return ids
    }()

    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    private var net: Net {
        settings.netList.first(where: { $0.id == netID }) ?? Net(id: netID)
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { net.durationMin }, set: { value in update { $0.durationMin = value } })
    }

    private var zoneBinding: Binding<String> {
        Binding(get: { net.timeZoneID }, set: { value in update { $0.timeZoneID = value } })
    }

    private var zoneChoices: [String] {
        Self.zones.contains(net.timeZoneID) ? Self.zones : Self.zones + [net.timeZoneID]
    }

    /// Round-trip the wall time through a Date so DatePicker can edit it
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = net.timeZone
                return calendar.date(
                    from: DateComponents(year: 2_000, month: 1, day: 1,
                                         hour: net.hour, minute: net.minute)
                ) ?? Date()
            },
            set: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = net.timeZone
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                update {
                    $0.hour = comps.hour ?? 0
                    $0.minute = comps.minute ?? 0
                }
            }
        )
    }

    private var weekdayRow: some View {
        HStack(spacing: 8) {
            ForEach(1 ... 7, id: \.self) { day in
                let selected = net.weekdays.contains(day)
                Button {
                    update { current in
                        if selected {
                            current.weekdays.removeAll { $0 == day }
                        } else {
                            current.weekdays.append(day)
                            current.weekdays.sort()
                        }
                    }
                } label: {
                    Text(Self.dayLetters[day - 1])
                        .font(CW.mono(13, medium: true))
                        .frame(width: 32, height: 32)
                        .background(selected ? CW.blue : CW.raised)
                        .foregroundStyle(selected ? CW.bg : CW.text)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func leadToggle(_ lead: Int, _ label: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { net.leads.contains(lead) },
            set: { enabled in
                update { current in
                    if enabled {
                        if !current.leads.contains(lead) {
                            current.leads.append(lead)
                        }
                    } else {
                        current.leads.removeAll { $0 == lead }
                    }
                }
            }
        ))
    }

    private func update(_ change: (inout Net) -> Void) {
        var list = settings.netList
        guard let index = list.firstIndex(where: { $0.id == netID }) else {
            return
        }
        change(&list[index])
        settings.netList = list
    }

    private func binding(_ keyPath: WritableKeyPath<Net, String>) -> Binding<String> {
        Binding(
            get: { net[keyPath: keyPath] },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }
}
