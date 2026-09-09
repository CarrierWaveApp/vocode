import Foundation

struct ASLNode: Identifiable {
    let node: String
    let callsign: String
    let desc: String
    let location: String

    var id: String { node }
}

// AllStarLink node directory. Ships with a bundled snapshot of the
// allmondb dump (node|callsign|description|location) and refreshes it in
// the background — the server is slow (~1.4 MB over ~30 s), so the
// snapshot keeps first launch instant. Node addresses come from ASL's
// DNS scheme at connect time, not from this list.
@MainActor
final class ASLDirectory: ObservableObject {
    static let shared = ASLDirectory()

    @Published private(set) var all: [ASLNode] = []
    @Published private(set) var refreshing = false

    private var loaded = false
    private static let refreshURL = URL(string: "https://allmondb.allstarlink.org/")!
    private static let maxCacheAge: TimeInterval = 7 * 86400

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("allstar-nodes.txt")
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        Task {
            let cached = Self.cacheFile
            let bundled = Bundle.main.url(forResource: "allstar-nodes", withExtension: "txt")
            let source = FileManager.default.fileExists(atPath: cached.path) ? cached : bundled
            if let source, let nodes = await Self.parse(url: source) {
                all = nodes
            }
            await refreshIfStale()
        }
    }

    func node(forNumber number: String) -> ASLNode? {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        return all.first { $0.node == trimmed }
    }

    private func refreshIfStale() async {
        let cached = Self.cacheFile
        if let modified = try? cached.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate,
           Date().timeIntervalSince(modified) < Self.maxCacheAge {
            return
        }
        refreshing = true
        defer { refreshing = false }
        var request = URLRequest(url: Self.refreshURL, timeoutInterval: 120)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > 100_000 else { return }
        try? data.write(to: cached)
        if let nodes = await Self.parse(url: cached) {
            all = nodes
        }
    }

    private static func parse(url: URL) async -> [ASLNode]? {
        await Task.detached(priority: .utility) { () -> [ASLNode]? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return text.split(separator: "\n").compactMap { line in
                guard !line.hasPrefix(";") else { return nil }
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 4, !parts[0].isEmpty else { return nil }
                return ASLNode(node: String(parts[0]), callsign: String(parts[1]),
                               desc: String(parts[2]),
                               location: String(parts[3]).trimmingCharacters(in: .whitespaces))
            }
        }.value
    }

    // MARK: - Node address resolution

    // ASL publishes each node's address in DNS: the TXT record for
    // <node>.nodes.allstarlink.org holds "NN=…" "IP=…" "PT=…". Plain
    // APIs can't query TXT, so ask a DNS-over-HTTPS resolver; if that
    // fails, fall back to the A record with the default IAX port.
    nonisolated static func resolve(node: String) async -> (host: String, port: UInt16) {
        let name = "\(node).nodes.allstarlink.org"
        let resolvers = [
            "https://cloudflare-dns.com/dns-query?name=\(name)&type=TXT",
            "https://dns.google/resolve?name=\(name)&type=TXT"
        ]
        for resolver in resolvers {
            guard let url = URL(string: resolver) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let parsed = parseDoHTXT(data) else { continue }
            return parsed
        }
        return (host: name, port: 4569)
    }

    nonisolated static func parseDoHTXT(_ data: Data) -> (host: String, port: UInt16)? {
        guard let response = try? JSONDecoder().decode(DoHResponse.self, from: data),
              let answers = response.answer else { return nil }
        for record in answers {
            var address: String?
            var port: UInt16?
            // TXT strings arrive quoted and space-joined:  "NN=2000" "IP=1.2.3.4" "PT=4569"
            for piece in record.data.split(whereSeparator: { "\" ".contains($0) }) {
                if piece.hasPrefix("IP=") { address = String(piece.dropFirst(3)) }
                if piece.hasPrefix("PT=") { port = UInt16(piece.dropFirst(3)) }
            }
            if let address { return (host: address, port: port ?? 4569) }
        }
        return nil
    }
}

private struct DoHResponse: Decodable {
    struct Record: Decodable {
        let data: String
    }
    let answer: [Record]?

    enum CodingKeys: String, CodingKey {
        case answer = "Answer"
    }
}
