import UIKit
import UserNotifications

// APNs registration, ported from hearth's Urithiru PushManager. Permission
// is requested only when buddy watch is first enabled — a user who never
// touches it never sees the prompt.
@MainActor
final class PushManager {
    static let shared = PushManager()

    // Latest APNs device token as hex, once the system vends one
    private(set) var deviceToken: String?

    // Fired whenever a token arrives; BuddyClient registers it server-side.
    // Re-fired on enable() when a token already exists.
    var onToken: ((String) -> Void)?

    private init() {}

    // Request permission only when undetermined; bail on denied; otherwise
    // (re-)register — idempotent, Apple-recommended per launch.
    func enable() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )) ?? false
                guard granted else { return }
            case .denied:
                return
            default:
                break
            }
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
        UNUserNotificationCenter.current().delegate = self
        return true
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

    // Show banners while foregrounded (iOS suppresses them by default)
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
