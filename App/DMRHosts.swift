import Foundation

// MARK: - DMRHost

/// One master server listed in Pi-Star's `DMR_Hosts.txt`.
///
/// Every entry here speaks the MMDVM dialect of the HomeBrew Repeater
/// Protocol — the `DestinationKind.hotspot` transport. BrandMeister's own
/// entries are dropped during parsing; see `DMRHostsDirectory`.
struct DMRHost: Identifiable, Equatable {
    /// The file's own name for the entry, e.g. `FD_AmComm_New_Jersey`.
    let name: String
    /// Network this entry was listed under, read from the section header
    /// above it in the file, e.g. `AmComm Network`.
    let network: String
    let host: String
    let password: String
    let port: UInt16

    /// Host and port identify a master; the same box is often listed under
    /// several names, and those are the same destination as far as we care.
    var id: String {
        "\(host):\(port)"
    }

    /// The file writes a literal `PASSWORD` where the network expects you to
    /// bring your own. Anything else is a working shared default, which is
    /// what lets a destination be configured without the user typing one.
    var needsOwnPassword: Bool {
        password == "PASSWORD"
    }

    /// `FD_AmComm_New_Jersey` → `AmComm New Jersey`. `FD` and `HB` are the
    /// file's own bookkeeping prefixes, not part of the network's name.
    var label: String {
        var parts = name.split(separator: "_").map(String.init)
        if let first = parts.first, first == "FD" || first == "HB" {
            parts.removeFirst()
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - DMRHostsDirectory

/// Master directory for Homebrew (MMDVM) destinations, parsed from Pi-Star's
/// `DMR_Hosts.txt` — the same list Pi-Star, WPSD and DroidStar read, so ports
/// and shared passwords stay right without us hardcoding them.
///
/// Ships with a bundled snapshot and refreshes in the background, the same
/// shape as `ASLDirectory`. The file is small (~80 KB), so unlike the AllStar
/// dump this is a quick fetch; the snapshot is there so the picker is
/// populated on first launch and offline.
///
/// Credit: the file is maintained by Andy Taylor (MW0MWZ) for Pi-Star.
@MainActor
final class DMRHostsDirectory: ObservableObject {
    // MARK: Internal

    static let shared = DMRHostsDirectory()

    @Published private(set) var all: [DMRHost] = []
    @Published private(set) var refreshing = false

    /// Networks in the order the file lists them, which groups by family and
    /// then by country — a better browse order than alphabetical.
    var networks: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.network).inserted ? $0.network : nil }
    }

    // MARK: - Parsing

    /// Parses the host-file text. Entries are
    /// `Name<tab>DMR-ID<tab>host<tab>password<tab>port`, with `#` comments;
    /// a comment of the form `# <network> Hosts Below` opens a section and
    /// names every entry under it.
    ///
    /// Two kinds of entry are dropped on purpose:
    ///
    /// - **BrandMeister.** BM prohibits radioless clients from speaking
    ///   either HBP dialect and NAKs them; a software client reaches BM over
    ///   Open Terminal instead (`DestinationKind.brandmeister`). Offering BM
    ///   masters in a Homebrew picker would only invite a rejected login.
    /// - **Loopback.** `DMRGateway`, `DMR2YSF` and `DMR2NXDN` are Pi-Star's
    ///   own internal 127.0.0.x plumbing, meaningless to us.
    nonisolated static func parse(_ text: String) -> [DMRHost] {
        var hosts: [DMRHost] = []
        var seen = Set<String>()
        var network = "Other"
        // The file mixes CRLF and LF line endings; splitting on newlines
        // alone leaves a \r glued to the port field.
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#") {
                if let named = sectionName(line) {
                    network = named
                }
                continue
            }
            guard let host = entry(line, network: network),
                  seen.insert(host.id).inserted
            else {
                continue
            }
            hosts.append(host)
        }
        return hosts
    }

    func loadIfNeeded() {
        guard !loaded else {
            return
        }
        loaded = true
        Task {
            let cached = Self.cacheFile
            let bundled = Bundle.main.url(forResource: "DMR_Hosts", withExtension: "txt")
            let source = FileManager.default.fileExists(atPath: cached.path) ? cached : bundled
            if let source, let parsed = await Self.parse(url: source) {
                all = parsed
            }
            await refreshIfStale()
        }
    }

    func hosts(network: String) -> [DMRHost] {
        all.filter { $0.network == network }
    }

    func host(matching host: String, port: UInt16) -> DMRHost? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return all.first { $0.host == trimmed && $0.port == port }
    }

    // MARK: Private

    // The `www.` host is the one with a valid certificate; the bare domain
    // 301s. Plain http would need an ATS exception, so keep this on https.
    private static let refreshURL = URL(string: "https://www.pistar.uk/downloads/DMR_Hosts.txt")!
    private static let maxCacheAge: TimeInterval = 7 * 86_400
    /// A healthy file is ~80 KB; anything tiny is an error page, not a list.
    private static let minPlausibleBytes = 10_000

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DMR_Hosts.txt")
    }

    private var loaded = false

    /// `#\t\tAmComm Network Hosts Below` → `AmComm Network`.
    nonisolated private static func sectionName(_ line: String) -> String? {
        let body = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        guard body.hasSuffix("Hosts Below") else {
            return nil
        }
        let name = body.dropLast("Hosts Below".count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    nonisolated private static func entry(_ line: String, network: String) -> DMRHost? {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 5,
              let port = UInt16(fields[fields.count - 1])
        else {
            return nil
        }
        let name = fields[0]
        let host = fields[fields.count - 3]
        // BM is unreachable over HBP for a radioless client, and Pi-Star's
        // loopback entries point at its own gateway.
        guard !name.hasPrefix("BM_"),
              !network.contains("BrandMeister"),
              !host.hasPrefix("127.")
        else {
            return nil
        }
        return DMRHost(name: name, network: network, host: host,
                       password: fields[fields.count - 2], port: port)
    }

    nonisolated private static func parse(url: URL) async -> [DMRHost]? {
        await Task.detached(priority: .utility) { () -> [DMRHost]? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            return parse(text)
        }.value
    }

    private func refreshIfStale() async {
        let cached = Self.cacheFile
        if let modified = try? cached.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate,
            Date().timeIntervalSince(modified) < Self.maxCacheAge
        {
            return
        }
        refreshing = true
        defer { refreshing = false }
        var request = URLRequest(url: Self.refreshURL, timeoutInterval: 30)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > Self.minPlausibleBytes
        else {
            return
        }
        try? data.write(to: cached)
        if let parsed = await Self.parse(url: cached) {
            all = parsed
        }
    }
}
