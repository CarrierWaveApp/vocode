import Foundation
import Combine

// One parsed line from a notes file
struct CallNote: Equatable {
    let call: String
    let note: String
    let source: String

    // Leading emoji, PoLo shows this in the log
    var emoji: String? {
        guard let first = note.first, first.isEmojiLike else { return nil }
        return String(first)
    }

    var text: String {
        guard emoji != nil else { return note }
        return String(note.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

struct CallNotesFile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var location: String
    var enabled: Bool
    var builtIn: Bool = false
    var lastFetched: Date?
    var entryCount: Int = 0
    var lastError: String?

    static let hamsOfNote = CallNotesFile(
        id: "ham2k-hams-of-note",
        name: "Ham2K's Hams of Note",
        location: "https://ham2k.com/data/hams-of-note.txt",
        enabled: true,
        builtIn: true
    )
}

// Same file format and lookup order as PoLo
@MainActor
final class CallNotesStore: ObservableObject {
    @Published private(set) var files: [CallNotesFile] = []
    @Published private(set) var refreshing: Set<String> = []

    private var notes: [String: [String: [CallNote]]] = [:]
    private let maxAge: TimeInterval = 86_400
    private let defaultsKey = "callNotesFiles"
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("callnotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadFiles()
        for f in files { loadCache(f) }
    }

    // MARK: - Lookup

    // First match wins, like PoLo findCallNotes
    func note(for call: String) -> CallNote? {
        let key = normalize(call)
        for f in files where f.enabled {
            if let hit = notes[f.id]?[key]?.first { return hit }
        }
        return nil
    }

    // All matches, like PoLo findAllCallNotes
    func allNotes(for call: String) -> [CallNote] {
        let key = normalize(call)
        return files.filter(\.enabled).flatMap { notes[$0.id]?[key] ?? [] }
    }

    // MARK: - File management

    func add(name: String, location: String) {
        let f = CallNotesFile(id: UUID().uuidString, name: name, location: location, enabled: true)
        files.append(f)
        saveFiles()
        Task { await refresh(f.id) }
    }

    func update(_ file: CallNotesFile) {
        guard let i = files.firstIndex(where: { $0.id == file.id }) else { return }
        let locationChanged = files[i].location != file.location
        files[i] = file
        saveFiles()
        if locationChanged { Task { await refresh(file.id) } }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        files[i].enabled = on
        saveFiles()
    }

    func remove(_ id: String) {
        guard let f = files.first(where: { $0.id == id }), !f.builtIn else { return }
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
        for f in files where f.enabled {
            let age = Date().timeIntervalSince(f.lastFetched ?? .distantPast)
            if age > maxAge { await refresh(f.id) }
        }
    }

    func refresh(_ id: String) async {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }

        do {
            let url = try await resolveDownloadURL(files[i].location)
            var req = URLRequest(url: url)
            req.setValue("DMRMonitor iOS/0.1", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let body = String(data: data, encoding: .utf8) else {
                throw NotesError.badResponse
            }
            let parsed = parse(body, source: files[i].name)
            notes[id] = parsed
            try? data.write(to: cacheURL(id))
            guard let j = files.firstIndex(where: { $0.id == id }) else { return }
            files[j].lastFetched = Date()
            files[j].entryCount = parsed.count
            files[j].lastError = nil
        } catch {
            guard let j = files.firstIndex(where: { $0.id == id }) else { return }
            files[j].lastError = "Failed to load"
        }
        saveFiles()
    }

    // MARK: - Parsing

    // One call per line, then the note
    func parse(_ body: String, source: String) -> [String: [CallNote]] {
        var out: [String: [CallNote]] = [:]
        for raw in body.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let callWord = words.first, callWord.count > 2, words.count > 1 else { continue }
            let call = normalize(String(callWord))
            let note = words.dropFirst().joined(separator: " ")
            out[call, default: []].append(CallNote(call: call, note: note, source: source))
        }
        return out
    }

    private func normalize(_ call: String) -> String {
        var c = call.uppercased()
        if c.hasSuffix("/") { c.removeLast() }
        return c
    }

    // MARK: - Share-link rewriting, mirrors PoLo resolveDownloadUrl

    func resolveDownloadURL(_ raw: String) async throws -> URL {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: s), let host = url.host?.lowercased() else {
            throw NotesError.badURL
        }

        if host.hasSuffix("dropbox.com") {
            var str = s.replacingOccurrences(of: #"[&?]raw=\d"#, with: "", options: .regularExpression)
            str = str.replacingOccurrences(of: #"[&?]dl=\d"#, with: "", options: .regularExpression)
            str += str.contains("?") ? "&dl=1&raw=1" : "?dl=1&raw=1"
            guard let u = URL(string: str) else { throw NotesError.badURL }
            return u
        }

        if host == "drive.google.com" {
            if let id = capture(s, #"file/d/([\w_-]+)"#) {
                url = URL(string: "https://drive.google.com/uc?id=\(id)&export=download")!
            }
            return url
        }

        if host == "docs.google.com", url.path.hasPrefix("/document") {
            if let id = capture(s, #"/d/([\w_-]+)"#) {
                url = URL(string: "https://docs.google.com/document/export?format=txt&id=\(id)")!
            }
            return url
        }

        if host == "gist.github.com" {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8),
               let path = capture(html, #"<a href="([^"]+/raw/[^"]+)""#),
               let u = URL(string: "https://gist.githubusercontent.com" + path) {
                return u
            }
            return url
        }

        if host.hasSuffix("icloud.com"), url.path.hasPrefix("/iclouddrive") {
            guard let guid = capture(s, #"iclouddrive/([\w_]+)"#) else { return url }
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
               let u = URL(string: dl) {
                return u
            }
            return url
        }

        return url
    }

    private func capture(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    // MARK: - Persistence

    private func cacheURL(_ id: String) -> URL {
        dir.appendingPathComponent(id).appendingPathExtension("txt")
    }

    private func loadCache(_ f: CallNotesFile) {
        guard let data = try? Data(contentsOf: cacheURL(f.id)),
              let body = String(data: data, encoding: .utf8) else { return }
        notes[f.id] = parse(body, source: f.name)
    }

    private func loadFiles() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([CallNotesFile].self, from: data),
           !saved.isEmpty {
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

enum NotesError: Error {
    case badURL
    case badResponse
}

extension Character {
    var isEmojiLike: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let p = scalar.properties
        return p.isEmojiPresentation || (p.isEmoji && scalar.value > 0x238C)
    }
}
