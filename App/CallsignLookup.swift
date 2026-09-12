import Foundation

struct CallsignInfo: Equatable {
    let callsign: String
    let name: String?
    let location: String?
}

/// radioid.net lookup with cache
actor CallsignLookup {
    private var cache: [UInt32: CallsignInfo] = [:]

    func callsign(for id: UInt32) async -> String? {
        await info(for: id)?.callsign
    }

    func info(for id: UInt32) async -> CallsignInfo? {
        if let hit = cache[id] {
            return hit
        }
        guard let url = URL(string: "https://radioid.net/api/dmr/user/?id=\(id)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let call = result["callsign"] as? String else { return nil }
        let name = [result["fname"] as? String, result["surname"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let location = [result["city"] as? String, result["state"] as? String, result["country"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let info = CallsignInfo(
            callsign: call,
            name: name.isEmpty ? nil : name,
            location: location.isEmpty ? nil : location
        )
        cache[id] = info
        return info
    }
}
