import UIKit
import UserNotifications

/// APNs registration, ported from hearth's Urithiru PushManager. Permission
/// is requested only when buddy watch is first enabled — a user who never
/// touches it never sees the prompt.
@MainActor
final class PushManager {
    static let shared = PushManager()

    /// Latest APNs device token as hex, once the system vends one
    private(set) var deviceToken: String?

    /// Fired whenever a token arrives; BuddyClient registers it server-side.
    /// Re-fired on enable() when a token already exists.
    var onToken: ((String) -> Void)?

    private init() {}

    /// Permission only, no APNs registration — nets reminders are local
    /// notifications and must not force remote-push setup
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Buddy watch: permission plus remote registration — idempotent,
    /// Apple-recommended per launch.
    func enable() {
        Task {
            guard await requestAuthorization() else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        onToken?(hex)
    }
}

final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Join needs the in-app UDP link, so the action foregrounds the app
        let join = UNNotificationAction(
            identifier: NetScheduler.joinAction, title: "Join",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NetScheduler.joinCategory, actions: [join],
                intentIdentifiers: [], options: []
            ),
        ])
        return true
    }

    /// A tapped net reminder (banner or Join action) parks a join intent.
    /// UserDefaults covers cold launch (this can run before any SwiftUI
    /// task); the post covers an already-foregrounded app.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard info["kind"] as? String == "net",
              let talkgroup = info["tg"] as? Int, talkgroup > 0,
              response.actionIdentifier == NetScheduler.joinAction
              || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }
        let defaults = UserDefaults.standard
        defaults.set(talkgroup, forKey: NetScheduler.pendingTGKey)
        defaults.set(info["name"] as? String ?? "", forKey: NetScheduler.pendingNameKey)
        NotificationCenter.default.post(name: NetScheduler.joinRequested, object: nil)
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushManager.shared.didRegister(tokenData: deviceToken) }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] remote registration failed: \(error.localizedDescription)")
    }

    /// Show banners while foregrounded (iOS suppresses them by default)
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
