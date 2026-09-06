import SwiftUI

struct CallNotesView: View {
    @EnvironmentObject var store: CallNotesStore
    @State private var editing: CallNotesFile?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(store.files) { file in
                    CallNotesRow(file: file, busy: store.refreshing.contains(file.id))
                        .contentShape(Rectangle())
                        .onTapGesture { editing = file }
                        .swipeActions(edge: .trailing) {
                            if !file.builtIn {
                                Button("Delete", role: .destructive) { store.remove(file.id) }
                            }
                            Button("Refresh") {
                                Task { await store.refresh(file.id) }
                            }
                            .tint(.blue)
                        }
                }
                .onMove { store.move(from: $0, to: $1) }
            } header: {
                SectionLabel("Files")
            } footer: {
                Text("Files are checked in order. First match wins.")
                    .font(CW.sans(12))
                    .foregroundStyle(CW.dim)
            }
            Section {
                Button("Add a new file") { adding = true }
                    .foregroundStyle(CW.blue)
            }
        }
        .cwList()
        .navigationTitle("Callsign notes")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { EditButton() }
        .sheet(item: $editing) { file in
            CallNotesEditor(file: file) { store.update($0) }
        }
        .sheet(isPresented: $adding) {
            CallNotesEditor(file: nil) { store.add(name: $0.name, location: $0.location) }
        }
    }
}

struct CallNotesRow: View {
    @EnvironmentObject var store: CallNotesStore
    let file: CallNotesFile
    let busy: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(CW.sans(15, .medium)).foregroundStyle(CW.white)
                Text(subtitle)
                    .font(CW.mono(11))
                    .foregroundStyle(file.lastError == nil ? CW.dim : CW.red)
            }
            Spacer()
            if busy {
                ProgressView()
            }
            Toggle("", isOn: Binding(
                get: { file.enabled },
                set: { store.setEnabled(file.id, $0) }
            ))
            .labelsHidden()
            .tint(CW.green)
        }
    }

    private var subtitle: String {
        if let err = file.lastError { return err }
        guard let when = file.lastFetched else { return "Not loaded yet" }
        return "\(file.entryCount) calls · \(when.formatted(.relative(presentation: .named)))"
    }
}

struct CallNotesEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: CallNotesFile?
    let onSave: (CallNotesFile) -> Void
    @State private var name: String
    @State private var location: String

    init(file: CallNotesFile?, onSave: @escaping (CallNotesFile) -> Void) {
        original = file
        self.onSave = onSave
        _name = State(initialValue: file?.name ?? "")
        _location = State(initialValue: file?.location ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("My notes", text: $name)
                        .disabled(original?.builtIn ?? false)
                } header: {
                    SectionLabel("Name")
                }
                Section {
                    TextField("https://…", text: $location, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(CW.mono(13))
                        .disabled(original?.builtIn ?? false)
                } header: {
                    SectionLabel("Location")
                } footer: {
                    Text("Direct link or share link from Dropbox, Google Drive, Google Docs, GitHub Gist, or iCloud Drive. One call per line, then the note.")
                }
            }
            .cwList()
            .navigationTitle(original == nil ? "New file" : "Edit file")
            .toolbarBackground(CW.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var f = original ?? CallNotesFile(id: "", name: "", location: "", enabled: true)
                        f.name = name.trimmingCharacters(in: .whitespaces)
                        f.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(f)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || location.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
