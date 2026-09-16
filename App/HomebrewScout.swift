import Foundation
import Network

// MARK: - HomebrewScout

/// Latency probe for Homebrew (MMDVM) masters, the counterpart to
/// `MasterScout` on the BrandMeister side.
///
/// Sends a single `RPTL` — the first packet of the HBP login — carrying an
/// **unregistered DMR ID of 0**, and times the reply. The master answers
/// either `MSTNAK` (it validates the ID up front) or `RPTACK` plus a salt
/// (it challenges first); both prove the DMR service is alive and neither
/// creates a session, because we never follow with `RPTK`.
///
/// The ID matters. Networks route on DMR ID, so probing with the operator's
/// real one risks knocking their own hotspot off the network — the ESSID
/// collision the DMR notes warn about. Zero sidesteps it and still draws a
/// reply, the same trick `MasterScout` uses against Rewind.
///
/// ICMP is deliberately not used here: measured against AmComm, five of
/// eleven masters filter ping while answering happily on 62031, so an echo
/// sweep would report working servers as dead.
final class HomebrewScout: ObservableObject {
    // MARK: Internal

    /// Probing every host of a large network at once would open hundreds of
    /// sockets for a list the user is only skimming. Callers pass a filtered
    /// network; this is the backstop.
    static let maxTargets = 64

    /// Unregistered, so the probe can never disturb a live session.
    static let probeID: UInt32 = 0

    @Published private(set) var results: [String: ProbeState] = [:]

    /// Fastest reachable target, by `DMRHost.id`.
    var fastest: String? {
        results
            .compactMap { key, value -> (String, Int)? in
                guard case let .reachable(millis) = value else {
                    return nil
                }
                return (key, millis)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// `RPTL` followed by the DMR ID as four big-endian bytes. HBP is
    /// big-endian here, unlike Rewind.
    static func loginFrame(dmrID: UInt32) -> Data {
        var frame = Data(login)
        frame.append(contentsOf: [UInt8(dmrID >> 24 & 0xFF), UInt8(dmrID >> 16 & 0xFF),
                                  UInt8(dmrID >> 8 & 0xFF), UInt8(dmrID & 0xFF)])
        return frame
    }

    /// A master is alive if it answered in the protocol at all. Both replies
    /// are expected — which one you get is a server-implementation detail.
    static func isLiveReply(_ data: Data?) -> Bool {
        guard let data, data.count >= 6 else {
            return false
        }
        let head = Array(data.prefix(6))
        return head == ack || head == nak
    }

    /// Probes each host; `completion` fires on the main queue once every
    /// probe settles, with the fastest reachable master or nil.
    ///
    /// Hosts are **not** collapsed by resolved address. Several masters
    /// commonly share one box — four AmComm entries answer on a single IP —
    /// but each carries its own DMR ID and is a distinct destination, so
    /// merging them would hide real choices behind an arbitrary winner.
    func probeAll(_ hosts: [DMRHost], completion: @escaping ((DMRHost, Int)?) -> Void = { _ in }) {
        cancelAll()
        self.completion = completion
        targets = Array(hosts.prefix(Self.maxTargets))
        pending = targets.count
        guard pending > 0 else {
            completion(nil)
            return
        }
        for target in targets {
            results[target.id] = .probing
            probe(target)
        }
    }

    /// Probes one host; used when the user picks a master by hand.
    func probeOne(_ host: DMRHost) {
        if !targets.contains(where: { $0.id == host.id }) {
            targets.append(host)
        }
        results[host.id] = .probing
        pending += 1
        probe(host)
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

    private static let timeout: TimeInterval = 2.5
    private static let login = Array("RPTL".utf8)
    private static let ack = Array("RPTACK".utf8)
    private static let nak = Array("MSTNAK".utf8)

    private let queue = DispatchQueue(label: "homebrew.scout")
    private var connections: [String: NWConnection] = [:]
    private var targets: [DMRHost] = []
    // Settle tracking, mirroring MasterScout: a generation counter keeps
    // probes from a superseded run out of a new one's results.
    private var pending = 0
    private var generation = 0
    private var completion: ((DMRHost, Int)?) -> Void = { _ in }

    /// Runs on main. Records one probe's outcome and fires the completion
    /// when this generation's last probe lands.
    private func settle(_ key: String, _ state: ProbeState, _ probeGeneration: Int) {
        guard probeGeneration == generation else {
            return
        }
        results[key] = state
        pending -= 1
        guard pending == 0 else {
            return
        }
        let done = completion
        completion = { _ in }
        if let fastestID = fastest,
           case let .reachable(millis)? = results[fastestID],
           let host = targets.first(where: { $0.id == fastestID })
        {
            done((host, millis))
        } else {
            done(nil)
        }
    }

    private func probe(_ target: DMRHost) {
        guard let nwPort = NWEndpoint.Port(rawValue: target.port) else {
            settle(target.id, .unreachable, generation)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: nwPort, using: .udp)
        connections[target.id] = connection
        let probeGeneration = generation
        let key = target.id

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
                connection.send(content: Self.loginFrame(dmrID: Self.probeID),
                                completion: .contentProcessed { _ in })
                connection.receiveMessage { data, _, _, _ in
                    guard let sent = sentAt, Self.isLiveReply(data) else {
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
