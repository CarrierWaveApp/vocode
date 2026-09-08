import Foundation

// A geocoded QRZ record; point == nil && grid == nil is a cached negative
struct QRZStation: Equatable, Codable, Sendable {
    let callsign: String
    let point: GeoPoint?
    let grid: String?
    let name: String?
    let country: String?
    let source: GeoSource?
    let fetched: Date

    var isNegative: Bool { point == nil && grid == nil }
    // Best available coordinates: exact fix, else grid center
    var bestPoint: GeoPoint? { point ?? grid.flatMap(Maidenhead.center) }
}

// QRZ XML API lookup: session-key auth, in-memory + disk cache, throttled
actor QRZLookup {
    private var username = ""
    private var password = ""
    private var sessionKey: String?
    private var credentialsBad = false
    private var cache: [String: QRZStation] = [:]
    private var cacheLoaded = false
    private var dirtyCount = 0
    private var inFlight: [String: Task<QRZStation?, Never>] = [:]
    private var lastRequest = Date.distantPast
    private let minInterval: TimeInterval = 0.25
    private let negativeTTL: TimeInterval = 86_400
    private let cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("qrzcache.json")
    }()

    var isConfigured: Bool { !username.isEmpty && !password.isEmpty && !credentialsBad }

    func configure(username user: String, password pass: String) {
        let trimmed = user.trimmingCharacters(in: .whitespaces)
        guard trimmed != username || pass != password else { return }
        username = trimmed
        password = pass
        sessionKey = nil
        credentialsBad = false
    }

    func station(for callsign: String) async -> QRZStation? {
        guard isConfigured else { return nil }
        loadCacheIfNeeded()
        let key = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let hit = cache[key] {
            if !hit.isNegative || Date().timeIntervalSince(hit.fetched) < negativeTTL {
                return hit.isNegative ? nil : hit
            }
        }
        if let pending = inFlight[key] {
            return await pending.value
        }
        let task = Task { await fetch(key) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    // MARK: - Network

    private func fetch(_ callsign: String) async -> QRZStation? {
        await throttle()
        guard let key = await session() else { return nil }
        guard let fields = await request(["s": key, "callsign": callsign]) else { return nil }

        // Missing session key or timeout error: re-auth once and retry once
        if fields["callsign.call"] == nil {
            let sessionError = fields["session.error"] ?? ""
            if fields["session.key"] == nil || sessionError.localizedCaseInsensitiveContains("timeout") {
                sessionKey = nil
                guard let fresh = await session(),
                      let retry = await request(["s": fresh, "callsign": callsign]) else { return nil }
                return record(callsign, from: retry)
            }
            return record(callsign, from: fields)
        }
        return record(callsign, from: fields)
    }

    private func record(_ callsign: String, from fields: [String: String]) -> QRZStation? {
        guard fields["callsign.call"] != nil else {
            // "Not found: X" comes back as a session error; cache the negative
            if fields["session.error"]?.localizedCaseInsensitiveContains("not found") == true {
                store(QRZStation(callsign: callsign, point: nil, grid: nil, name: nil,
                                 country: nil, source: nil, fetched: Date()))
            }
            return nil
        }
        var point: GeoPoint?
        if let lat = fields["callsign.lat"].flatMap(Double.init),
           let lon = fields["callsign.lon"].flatMap(Double.init) {
            point = GeoPoint(lat: lat, lon: lon)
        }
        let grid = fields["callsign.grid"]
        let source: GeoSource?
        switch fields["callsign.geoloc"] {
        case "user", "geocode": source = .qrz
        case "grid": source = .grid
        case "dxcc": source = .dxcc
        default: source = point != nil ? .qrz : (grid != nil ? .grid : nil)
        }
        let name = [fields["callsign.fname"], fields["callsign.name"]]
            .compactMap { $0 }.joined(separator: " ")
        let station = QRZStation(
            callsign: callsign,
            point: point,
            grid: grid,
            name: name.isEmpty ? nil : name,
            country: fields["callsign.country"],
            source: source,
            fetched: Date()
        )
        store(station)
        return station.isNegative ? nil : station
    }

    private func session() async -> String? {
        if let sessionKey { return sessionKey }
        guard !credentialsBad else { return nil }
        let fields = await request([
            "username": username, "password": password, "agent": "dmrmonitor1.0"
        ])
        if let key = fields?["session.key"] {
            sessionKey = key
            return key
        }
        let error = fields?["session.error"] ?? "no response"
        if error.localizedCaseInsensitiveContains("incorrect") ||
            error.localizedCaseInsensitiveContains("invalid") {
            credentialsBad = true
        }
        return nil
    }

    // QRZ uses ;-separated params; percent-encode values (passwords may hold ;&=)
    private func request(_ params: [String: String]) async -> [String: String]? {
        let query = params.map { key, val in
            "\(key)=\(val.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? val)"
        }.joined(separator: ";")
        guard let url = URL(string: "https://xmldata.qrz.com/xml/current/?\(query)"),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        let parser = QRZXMLCollector()
        return parser.parse(data)
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()
    }

    // MARK: - Disk cache

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let stored = try? JSONDecoder().decode([String: QRZStation].self, from: data)
        else { return }
        cache = stored
    }

    private func store(_ station: QRZStation) {
        cache[station.callsign] = station
        dirtyCount += 1
        if dirtyCount >= 20 { flush() }
    }

    func flush() {
        guard dirtyCount > 0, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        dirtyCount = 0
    }
}

// Flattens <Session>/<Callsign> children into "section.element" keys
private final class QRZXMLCollector: NSObject, XMLParserDelegate {
    private var fields: [String: String] = [:]
    private var section = ""
    private var element = ""
    private var text = ""

    func parse(_ data: Data) -> [String: String]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return fields.isEmpty ? nil : fields }
        return fields
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let lowered = name.lowercased()
        if lowered == "session" || lowered == "callsign" {
            section = lowered
        } else {
            element = lowered
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let lowered = name.lowercased()
        guard lowered == element, !section.isEmpty else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            fields["\(section).\(lowered)"] = value
        }
        element = ""
    }
}
