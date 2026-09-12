import Foundation
import UserNotifications

/// One watched station. The app owns the list; the server holds a replica
/// replaced wholesale on every sync.
struct Buddy: Codable, Identifiable, Equatable {
    var id: UUID
    var callsign: String
    var dmrID: UInt32
    var label: String
    var talkgroups: [UInt32]

    init(id: UUID = UUID(), callsign: String = "", dmrID: UInt32 = 0,
         label: String = "", talkgroups: [UInt32] = [])
    {
        self.id = id
        self.callsign = callsign
        self.dmrID = dmrID
        self.label = label
        self.talkgroups = talkgroups
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        callsign = try values.decodeIfPresent(String.self, forKey: .callsign) ?? ""
        dmrID = try values.decodeIfPresent(UInt32.self, forKey: .dmrID) ?? 0
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? ""
        talkgroups = try values.decodeIfPresent([UInt32].self, forKey: .talkgroups) ?? []
    }
}

enum BuddyStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

/// Talks to the dmr-lookout server: device registration + watch-list sync.
@MainActor
final class BuddyClient: ObservableObject {
    @Published var status: BuddyStatus = .idle

    /// Wire the APNs token callback and kick a registration if enabled.
    /// Idempotent; called from the root view's task. Every bail-out sets a
    /// visible status — a silent "idle" cost a debugging round once.
    func startup(_ settings: Settings) {
        PushManager.shared.onToken = { [weak self] token in
            Task { await self?.registerAndSync(settings, apnsToken: token) }
        }
        guard settings.buddyWatchEnabled else { return }
        if settings.buddyDeviceID.isEmpty {
            settings.buddyDeviceID = UUID().uuidString
        }
        guard settings.buddyConfigured else {
            status = .failed("enter server URL + API token")
            return
        }
        Task {
            let auth = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
            if auth == .denied {
                status = .failed("notifications denied — enable in iOS Settings")
                return
            }
            status = .syncing
            PushManager.shared.enable()
            // If iOS never vends a token, say so instead of spinning
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if case .syncing = status, settings.buddyLastToken.isEmpty {
                status = .failed("no push token from iOS")
            }
        }
    }

    func registerAndSync(_ settings: Settings, apnsToken: String) async {
        guard settings.buddyWatchEnabled, settings.buddyConfigured else { return }
        status = .syncing
        do {
            if apnsToken != settings.buddyLastToken {
                // Debug (xc deploy) builds vend sandbox APNs tokens;
                // Release (TestFlight/App Store) builds vend production
                #if DEBUG
                    let apnsEnv = "sandbox"
                #else
                    let apnsEnv = "production"
                #endif
                try await post(settings, path: "/v1/devices", body: [
                    "device_id": settings.buddyDeviceID,
                    "apns_token": apnsToken,
                    "apns_env": apnsEnv,
                    "platform": "ios",
                    "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                        as? String ?? "",
                ])
                settings.buddyLastToken = apnsToken
                // A fresh registration must re-sync regardless of list hash
                settings.buddyLastSynced = ""
            }
            try await syncWatches(settings)
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// PUT the whole list; the app is the source of truth
    func syncWatches(_ settings: Settings) async throws {
        let list = settings.buddyList.map { buddy in
            [
                "callsign": buddy.callsign,
                "dmr_id": buddy.dmrID,
                "label": buddy.label,
                "talkgroups": buddy.talkgroups,
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: list)
        let hash = String(data.hashValue)
        guard hash != settings.buddyLastSynced else { return }
        try await send(settings, path: "/v1/devices/\(settings.buddyDeviceID)/watches",
                       method: "PUT", body: data)
        settings.buddyLastSynced = hash
    }

    /// Re-sync if the list changed since the last successful PUT. A device
    /// that never registered (no token POSTed yet) needs the full startup
    /// path first — a bare watch PUT for an unknown device can't succeed.
    func syncIfNeeded(_ settings: Settings) {
        guard settings.buddyWatchEnabled, settings.buddyConfigured,
              !settings.buddyDeviceID.isEmpty else { return }
        if settings.buddyLastToken.isEmpty {
            if let token = PushManager.shared.deviceToken {
                Task { await registerAndSync(settings, apnsToken: token) }
            } else {
                startup(settings)
            }
            return
        }
        Task {
            status = .syncing
            do {
                try await syncWatches(settings)
                status = .synced(Date())
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func sendTest(_ settings: Settings) async -> String? {
        do {
            try await post(settings, path: "/v1/devices/\(settings.buddyDeviceID)/test",
                           body: [:])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Best-effort deregistration when the toggle goes off
    func deregister(_ settings: Settings) {
        guard settings.buddyConfigured, !settings.buddyDeviceID.isEmpty else { return }
        settings.buddyLastToken = ""
        settings.buddyLastSynced = ""
        let path = "/v1/devices/\(settings.buddyDeviceID)"
        Task { try? await send(settings, path: path, method: "DELETE", body: nil) }
    }

    /// Resolve a callsign to its DMR ID via radioid.net (the inverse of
    /// CallsignLookup); best-effort at buddy-add time
    static func dmrID(forCallsign call: String) async -> UInt32? {
        let normalized = call.trimmingCharacters(in: .whitespaces).uppercased()
        guard !normalized.isEmpty,
              let url = URL(string: "https://radioid.net/api/dmr/user/?callsign=\(normalized)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return nil }
        let ids = results.compactMap { $0["id"] as? UInt32 }
        return ids.min()
    }

    // MARK: - HTTP

    private func post(_ settings: Settings, path: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        try await send(settings, path: path, method: "POST", body: data)
    }

    private func send(_ settings: Settings, path: String, method: String,
                      body: Data?) async throws
    {
        guard let url = URL(string: settings.buddyServerURL + path) else {
            throw BuddyError.badURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(settings.buddyAPIToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (payload, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BuddyError.badResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(bytes: payload, encoding: .utf8) ?? ""
            throw BuddyError.server(http.statusCode, text)
        }
    }
}

enum BuddyError: LocalizedError {
    case badURL
    case badResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "bad server URL"
        case .badResponse: return "bad response"
        case let .server(code, text):
            return text.isEmpty ? "server error \(code)" : "\(code): \(text)"
        }
    }
}
