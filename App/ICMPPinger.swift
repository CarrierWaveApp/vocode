import Foundation

/// One-socket ICMP echo sweep for the reflector picker. Unprivileged
/// SOCK_DGRAM ICMP, the same mechanism Apple's SimplePing uses; on
/// Darwin replies arrive with the 20-byte IP header still attached.
/// Results are keyed by IP and flushed to the published dictionary in
/// batches so an 800-target sweep doesn't invalidate the view per reply.
final class ICMPPinger: ObservableObject {
    @Published private(set) var results: [String: ProbeState] = [:]

    private let queue = DispatchQueue(label: "icmp.ping")
    private var sock: Int32 = -1
    private var reader: DispatchSourceRead?
    private var flusher: Timer?
    private var pendingBySeq: [UInt16: (ip: String, sentAt: Date)] = [:]
    private var fresh: [String: ProbeState] = [:]
    private var nextSeq: UInt16 = 1

    private static let timeout: TimeInterval = 2.5

    deinit {
        if sock >= 0 { close(sock) }
    }

    // Called from the main thread
    func ping(_ ips: [String]) {
        cancel()
        let targets = Array(Set(ips)).filter { !$0.isEmpty }
        guard !targets.isEmpty else { return }
        for address in targets { results[address] = .probing }

        let icmpSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard icmpSock >= 0 else {
            for address in targets { results[address] = .unreachable }
            return
        }
        sock = icmpSock
        let flags = fcntl(icmpSock, F_GETFL, 0)
        _ = fcntl(icmpSock, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: icmpSock, queue: queue)
        source.setEventHandler { [weak self] in self?.drainReplies() }
        reader = source
        source.resume()

        queue.async { [weak self] in self?.sendAll(targets) }
        queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in self?.finishSweep() }

        flusher = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    func cancel() {
        flusher?.invalidate()
        flusher = nil
        queue.sync {
            reader?.cancel()
            reader = nil
            if sock >= 0 {
                close(sock)
                sock = -1
            }
            pendingBySeq = [:]
            fresh = [:]
        }
    }

    // MARK: - Queue side

    private func sendAll(_ addresses: [String]) {
        for address in addresses {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else {
                fresh[address] = .unreachable
                continue
            }
            let seq = nextSeq
            nextSeq &+= 1
            var packet: [UInt8] = [8, 0, 0, 0, 0, 0, UInt8(seq >> 8), UInt8(seq & 0xFF)]
            let sum = Self.checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xFF)
            pendingBySeq[seq] = (address, Date())
            let sent = withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saptr in
                    sendto(sock, packet, packet.count, 0, saptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent < 0 {
                pendingBySeq[seq] = nil
                fresh[address] = .unreachable
            }
        }
    }

    private func drainReplies() {
        var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = recv(sock, &buf, buf.count, 0)
            guard count >= 28 else { return }
            let ihl = Int(buf[0] & 0x0F) * 4
            guard count >= ihl + 8, buf[ihl] == 0 else { continue }
            let seq = UInt16(buf[ihl + 6]) << 8 | UInt16(buf[ihl + 7])
            guard let target = pendingBySeq.removeValue(forKey: seq) else { continue }
            let millis = Int(Date().timeIntervalSince(target.sentAt) * 1000)
            fresh[target.ip] = .reachable(millis: millis)
        }
    }

    private func finishSweep() {
        for target in pendingBySeq.values where fresh[target.ip] == nil {
            fresh[target.ip] = .unreachable
        }
        pendingBySeq = [:]
        reader?.cancel()
        reader = nil
        if sock >= 0 {
            close(sock)
            sock = -1
        }
        DispatchQueue.main.async { [weak self] in
            self?.flush()
            self?.flusher?.invalidate()
            self?.flusher = nil
        }
    }

    // MARK: - Main side

    private func flush() {
        var batch: [String: ProbeState] = [:]
        queue.sync {
            batch = fresh
            fresh = [:]
        }
        guard !batch.isEmpty else { return }
        for (address, state) in batch { results[address] = state }
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum &+= UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum &+= UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) &+ (sum >> 16) }
        return UInt16(~sum & 0xFFFF)
    }
}
