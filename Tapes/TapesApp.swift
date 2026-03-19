import SwiftUI
import UserNotifications

@main
struct TapesApp: App {
    @StateObject private var tapeStore = TapesStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var entitlementManager = EntitlementManager()

    private static let notificationHandler = ExportNotificationHandler()

    init() {
        cleanupTempImports()
        UNUserNotificationCenter.current().delegate = Self.notificationHandler
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tapeStore)
                .environmentObject(authManager)
                .environmentObject(entitlementManager)
        }
    }
}

final class ExportNotificationHandler: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["action"] as? String == "openPhotos" {
            if let url = URL(string: "photos-redirect://") {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
