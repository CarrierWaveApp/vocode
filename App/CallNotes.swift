import Combine
import Foundation

// MARK: - CallNote

/// One parsed line from a notes file
struct CallNote: Equatable {
    let call: String
    let note: String
    let source: String

    /// Leading emoji, PoLo shows this in the log
    var emoji: String? {
        guard let first = note.first, first.isEmojiLike else {
            return nil
        }
        return String(first)
    }

    var text: String {
        guard emoji != nil else {
            return note
        }
        return String(note.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - CallNotesFile

struct CallNotesFile: Identifiable, Codable, Equatable {
    static let hamsOfNote = CallNotesFile(
        id: "ham2k-hams-of-note",
        name: "Ham2K's Hams of Note",
        location: "https://ham2k.com/data/hams-of-note.txt",
        enabled: true,
        builtIn: true
    )

    var id: String
    var name: String
    var location: String
    var enabled: Bool
    var builtIn: Bool = false
    var lastFetched: Date?
    var entryCount: Int = 0
    var lastError: String?
}

// MARK: - CallNotesStore

/// Same file format and lookup order as PoLo
@MainActor
final class CallNotesStore: ObservableObject {
    // MARK: Lifecycle

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("callnotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadFiles()
        for file in files {
            loadCache(file)
        }
    }

    // MARK: Internal

    @Published private(set) var files: [CallNotesFile] = []
    @Published private(set) var refreshing: Set<String> = []

    // MARK: - Lookup

    /// First match wins, like PoLo findCallNotes
    func note(for call: String) -> CallNote? {
        let key = normalize(call)
        for file in files where file.enabled {
            if let hit = notes[file.id]?[key]?.first {
                return hit
            }
        }
        return nil
    }

    /// All matches, like PoLo findAllCallNotes
    func allNotes(for call: String) -> [CallNote] {
        let key = normalize(call)
        return files.filter(\.enabled).flatMap { notes[$0.id]?[key] ?? [] }
    }

    // MARK: - File management

    func add(name: String, location: String) {
        let newFile = CallNotesFile(id: UUID().uuidString, name: name, location: location, enabled: true)
        files.append(newFile)
        saveFiles()
        Task { await refresh(newFile.id) }
    }

    func update(_ file: CallNotesFile) {
        guard let i = files.firstIndex(where: { $0.id == file.id }) else {
            return
        }
        let locationChanged = files[i].location != file.location
        files[i] = file
        saveFiles()
        if locationChanged {
            Task { await refresh(file.id) }
        }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let i = files.firstIndex(where: { $0.id == id }) else {
            return
        }
        files[i].enabled = on
        saveFiles()
    }

    func remove(_ id: String) {
        guard let file = files.first(where: { $0.id == id }), !file.builtIn else {
            return
        }
        files.removeAll { $0.id == id }
        notes[id] = nil
        try? FileManager.default.removeItem(at: cacheURL(id))
        saveFiles()
    }

    func move(from: IndexSet, to: Int) {
        files.move(fromOffsets: from, toOffset: to)
        saveFiles()
    }

    func refreshStale() async {
        for file in files where file.enabled {
            let age = Date().timeIntervalSince(file.lastFetched ?? .distantPast)
            if age > maxAge {
                await refresh(file.id)
            }
        }
    }

    func refresh(_ id: String) async {
        guard let i = files.firstIndex(where: { $0.id == id }) else {
            return
        }
        refreshing.insert(id)
        defer { refreshing.remove(id) }

        do {
            let url = try await resolveDownloadURL(files[i].location)
            var req = URLRequest(url: url)
            req.setValue("DMRMonitor iOS/0.1", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let body = String(data: data, encoding: .utf8)
            else {
                throw NotesError.badResponse
            }
            let parsed = parse(body, source: files[i].name)
            notes[id] = parsed
            try? data.write(to: cacheURL(id))
            guard let j = files.firstIndex(where: { $0.id == id }) else {
                return
            }
            files[j].lastFetched = Date()
            files[j].entryCount = parsed.count
            files[j].lastError = nil
        } catch {
            guard let j = files.firstIndex(where: { $0.id == id }) else {
                return
            }
            files[j].lastError = "Failed to load"
        }
        saveFiles()
    }

    // MARK: - Parsing

    /// One call per line, then the note
    func parse(_ body: String, source: String) -> [String: [CallNote]] {
        var out: [String: [CallNote]] = [:]
        for raw in body.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let callWord = words.first, callWord.count > 2, words.count > 1 else {
                continue
            }
            let call = normalize(String(callWord))
            let note = words.dropFirst().joined(separator: " ")
            out[call, default: []].append(CallNote(call: call, note: note, source: source))
        }
        return out
    }

    // MARK: - Share-link rewriting, mirrors PoLo resolveDownloadUrl

    func resolveDownloadURL(_ raw: String) async throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: trimmed), let host = url.host?.lowercased() else {
            throw NotesError.badURL
        }

        if host.hasSuffix("dropbox.com") {
            return try resolveDropboxURL(trimmed)
        }

        if host == "drive.google.com" {
            if let id = capture(trimmed, #"file/d/([\w_-]+)"#) {
                url = URL(string: "https://drive.google.com/uc?id=\(id)&export=download")!
            }
            return url
        }

        if host == "docs.google.com", url.path.hasPrefix("/document") {
            if let id = capture(trimmed, #"/d/([\w_-]+)"#) {
                url = URL(string: "https://docs.google.com/document/export?format=txt&id=\(id)")!
            }
            return url
        }

        if host == "gist.github.com" {
            return try await resolveGistURL(trimmed, fallback: url)
        }

        if host.hasSuffix("icloud.com"), url.path.hasPrefix("/iclouddrive") {
            return try await resolveICloudDriveURL(trimmed, fallback: url)
        }

        return url
    }

    // MARK: Private

    private var notes: [String: [String: [CallNote]]] = [:]
    private let maxAge: TimeInterval = 86_400
    private let defaultsKey = "callNotesFiles"
    private let dir: URL

    private func resolveDropboxURL(_ trimmed: String) throws -> URL {
        var str = trimmed.replacingOccurrences(of: #"[&?]raw=\d"#, with: "", options: .regularExpression)
        str = str.replacingOccurrences(of: #"[&?]dl=\d"#, with: "", options: .regularExpression)
        str += str.contains("?") ? "&dl=1&raw=1" : "?dl=1&raw=1"
        guard let resolved = URL(string: str) else {
            throw NotesError.badURL
        }
        return resolved
    }

    private func resolveGistURL(_ trimmed: String, fallback: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: fallback)
        if let html = String(data: data, encoding: .utf8),
           let path = capture(html, #"<a href="([^"]+/raw/[^"]+)""#),
           let resolved = URL(string: "https://gist.githubusercontent.com" + path)
        {
            return resolved
        }
        return fallback
    }

    private func resolveICloudDriveURL(_ trimmed: String, fallback: URL) async throws -> URL {
        guard let guid = capture(trimmed, #"iclouddrive/([\w_]+)"#) else {
            return fallback
        }
        var req = URLRequest(url: URL(string:
            "https://ckdatabasews.icloud.com/database/1/com.apple.cloudkit/production/public/records/resolve")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["shortGUIDs": [["value": guid]]])
        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let root = results.first?["rootRecord"] as? [String: Any],
           let fields = root["fields"] as? [String: Any],
           let content = fields["fileContent"] as? [String: Any],
           let value = content["value"] as? [String: Any],
           let dl = value["downloadURL"] as? String,
           let resolved = URL(string: dl)
        {
            return resolved
        }
        return fallback
    }

    private func normalize(_ call: String) -> String {
        var normalized = call.uppercased()
        if normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func capture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    // MARK: - Persistence

    private func cacheURL(_ id: String) -> URL {
        dir.appendingPathComponent(id).appendingPathExtension("txt")
    }

    private func loadCache(_ file: CallNotesFile) {
        guard let data = try? Data(contentsOf: cacheURL(file.id)),
              let body = String(data: data, encoding: .utf8)
        else {
            return
        }
        notes[file.id] = parse(body, source: file.name)
    }

    private func loadFiles() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([CallNotesFile].self, from: data),
           !saved.isEmpty
        {
            files = saved
        } else {
            files = [.hamsOfNote]
        }
        if !files.contains(where: { $0.id == CallNotesFile.hamsOfNote.id }) {
            files.insert(.hamsOfNote, at: 0)
        }
    }

    private func saveFiles() {
        if let data = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

// MARK: - NotesError

enum NotesError: Error {
    case badURL
    case badResponse
}

extension Character {
    var isEmojiLike: Bool {
        guard let scalar = unicodeScalars.first else {
            return false
        }
        let properties = scalar.properties
        return properties.isEmojiPresentation || (properties.isEmoji && scalar.value > 0x238C)
    }
}
