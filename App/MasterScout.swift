import Foundation
import Network

// MARK: - BMMaster

// "Master" is BrandMeister's own name for its servers; renaming here would
// diverge from the protocol and every piece of BM documentation.
// swiftlint:disable inclusive_language

/// One BrandMeister master server.
struct BMMaster: Identifiable {
    let id: UInt16
    let country: String

    var host: String {
        "\(id).master.brandmeister.network"
    }
}

// MARK: - BMDirectory

/// Masters grouped for the picker. Static on purpose: BrandMeister has no
/// public directory API, the set changes rarely, and a stale entry is
/// harmless because the latency probe shows it as unreachable.
/// Verified against DNS on 2026-09-06 (3101 no longer exists, for example).
enum BMDirectory {
    static let regions: [(name: String, masters: [BMMaster])] = [
        ("North America", [
            BMMaster(id: 3_021, country: "Canada"),
            BMMaster(id: 3_102, country: "United States"),
            BMMaster(id: 3_103, country: "United States"),
            BMMaster(id: 3_104, country: "United States"),
            BMMaster(id: 3_341, country: "Mexico"),
        ]),
        ("Europe", [
            BMMaster(id: 2_322, country: "Austria"),
            BMMaster(id: 2_061, country: "Belgium"),
            BMMaster(id: 2_841, country: "Bulgaria"),
            BMMaster(id: 2_842, country: "Bulgaria"),
            BMMaster(id: 2_302, country: "Czechia"),
            BMMaster(id: 2_382, country: "Denmark"),
            BMMaster(id: 2_441, country: "Finland"),
            BMMaster(id: 2_081, country: "France"),
            BMMaster(id: 2_082, country: "France"),
            BMMaster(id: 2_621, country: "Germany"),
            BMMaster(id: 2_622, country: "Germany"),
            BMMaster(id: 2_022, country: "Greece"),
            BMMaster(id: 2_162, country: "Hungary"),
            BMMaster(id: 2_721, country: "Ireland"),
            BMMaster(id: 2_222, country: "Italy"),
            BMMaster(id: 2_041, country: "Netherlands"),
            BMMaster(id: 2_421, country: "Norway"),
            BMMaster(id: 2_602, country: "Poland"),
            BMMaster(id: 2_681, country: "Portugal"),
            BMMaster(id: 2_682, country: "Portugal"),
            BMMaster(id: 2_262, country: "Romania"),
            BMMaster(id: 2_501, country: "Russia"),
            BMMaster(id: 2_502, country: "Russia"),
            BMMaster(id: 2_503, country: "Russia"),
            BMMaster(id: 2_931, country: "Slovenia"),
            BMMaster(id: 2_141, country: "Spain"),
            BMMaster(id: 2_402, country: "Sweden"),
            BMMaster(id: 2_282, country: "Switzerland"),
            BMMaster(id: 2_551, country: "Ukraine"),
            BMMaster(id: 2_341, country: "United Kingdom"),
        ]),
        ("Asia & Middle East", [
            BMMaster(id: 4_602, country: "China"),
            BMMaster(id: 4_251, country: "Israel"),
            BMMaster(id: 5_021, country: "Malaysia"),
            BMMaster(id: 5_151, country: "Philippines"),
            BMMaster(id: 4_501, country: "South Korea"),
        ]),
        ("Oceania", [
            BMMaster(id: 5_051, country: "Australia"),
        ]),
        ("Africa", [
            BMMaster(id: 6_551, country: "South Africa"),
        ]),
        ("South America", [
            BMMaster(id: 7_242, country: "Brazil"),
            BMMaster(id: 7_301, country: "Chile"),
        ]),
    ]

    static var all: [BMMaster] {
        regions.flatMap(\.masters)
    }

    static func master(forHost host: String) -> BMMaster? {
        all.first { $0.host == host.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - ProbeState

enum ProbeState: Equatable {
    case probing
    case reachable(millis: Int)
    case unreachable
}

// MARK: - MasterScout

/// Probes each master with a single Rewind keep-alive datagram and times the
/// reply. The Open Terminal login flow starts with the client's keep-alive
/// and the master's challenge comes back before any authentication, so this
/// measures the actual DMR service with one packet each way and never logs in.
final class MasterScout: ObservableObject {
    // MARK: Internal

    static let openTerminalPort: UInt16 = 54_006
    /// Key in `results` for a custom (non-directory) host probe.
    static let customKey: UInt16 = 0

    @Published private(set) var results: [UInt16: ProbeState] = [:]

    var fastest: UInt16? {
        results
            .filter { $0.key != Self.customKey }
            .compactMap { key, value -> (UInt16, Int)? in
                guard case let .reachable(millis) = value else {
                    return nil
                }
                return (key, millis)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Probes every master; `completion` fires on the main queue once all
    /// probes settle, with the fastest reachable master or nil.
    func probeAll(dmrID: UInt32, completion: @escaping ((BMMaster, Int)?) -> Void = { _ in }) {
        cancelAll()
        self.completion = completion
        pending = BMDirectory.all.count
        for master in BMDirectory.all {
            results[master.id] = .probing
            probe(key: master.id, host: master.host, port: Self.openTerminalPort, dmrID: dmrID)
        }
    }

    /// Probes just one master; used by Settings for the selected one.
    func probeOne(_ master: BMMaster, dmrID: UInt32) {
        results[master.id] = .probing
        pending += 1
        probe(key: master.id, host: master.host, port: Self.openTerminalPort, dmrID: dmrID)
    }

    /// Probes a custom host and port; the result lands under `customKey`.
    func probeCustom(host: String, port: UInt16, dmrID: UInt32) {
        results[Self.customKey] = .probing
        pending += 1
        probe(key: Self.customKey, host: host, port: port, dmrID: dmrID)
    }

    func cancelAll() {
        completion = { _ in }
        pending = 0
        generation += 1
        for connection in connections.values {
            connection.cancel()
        }
        connections = [:]
    }

    // MARK: Private

    private static let sign = Array("REWIND01".utf8)
    private static let timeout: TimeInterval = 2.5

    private let queue = DispatchQueue(label: "master.scout")
    private var connections: [UInt16: NWConnection] = [:]
    // Settle tracking for the completion callback. A generation counter
    // guards against probes from a superseded run reporting into a new one.
    private var pending = 0
    private var generation = 0
    private var completion: ((BMMaster, Int)?) -> Void = { _ in }

    /// Mirrors RewindClient's framing: sign, type, flags, sequence, payload
    /// length, payload. Type 0x0000 is keep-alive with the Open Terminal
    /// service identifier; ID 0 still draws a challenge from the master.
    private static func keepAliveFrame(dmrID: UInt32) -> Data {
        var payload = Data()
        payload.append(le32(dmrID))
        payload.append(0x21)
        payload.append(contentsOf: Array("DMRMonitor scout".utf8))

        var frame = Data(sign)
        frame.append(le16(0x0000))
        frame.append(le16(0))
        frame.append(le32(0))
        frame.append(le16(UInt16(payload.count)))
        frame.append(payload)
        return frame
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }

    /// Runs on main. Records one probe's outcome and fires the completion
    /// when this generation's last probe lands.
    private func settle(_ masterID: UInt16, _ state: ProbeState, _ probeGeneration: Int) {
        guard probeGeneration == generation else {
            return
        }
        results[masterID] = state
        pending -= 1
        guard pending == 0 else {
            return
        }
        let done = completion
        completion = { _ in }
        if let fastestID = fastest,
           case let .reachable(millis)? = results[fastestID],
           let master = BMDirectory.all.first(where: { $0.id == fastestID })
        {
            done((master, millis))
        } else {
            done(nil)
        }
    }

    private func probe(key: UInt16, host: String, port: UInt16, dmrID: UInt32) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connections[key] = connection
        let probeGeneration = generation

        // Everything below runs on `queue`, so these are single-threaded.
        var sentAt: Date?
        var done = false

        func finish(_ state: ProbeState) {
            guard !done else {
                return
            }
            done = true
            connection.cancel()
            DispatchQueue.main.async { self.settle(key, state, probeGeneration) }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sentAt = Date()
                connection.send(content: Self.keepAliveFrame(dmrID: dmrID),
                                completion: .contentProcessed { _ in })
                connection.receiveMessage { data, _, _, _ in
                    guard let sent = sentAt, data != nil else {
                        finish(.unreachable)
                        return
                    }
                    finish(.reachable(millis: Int(Date().timeIntervalSince(sent) * 1_000)))
                }
            case .failed,
                 .cancelled:
                finish(.unreachable)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.timeout) { finish(.unreachable) }
    }
}

// swiftlint:enable inclusive_language
