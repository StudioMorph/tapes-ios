import UIKit
import UserNotifications
import os

final class PushNotificationManager: NSObject, ObservableObject {

    static let shared = PushNotificationManager()

    var apiClient: TapesAPIClient?
    var navigationCoordinator: NavigationCoordinator?

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Push")

    private override init() {
        super.init()
    }

    // MARK: - Registration

    func requestAuthorisation() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            if let error {
                self?.log.error("Push auth error: \(error.localizedDescription)")
                return
            }

            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self?.log.info("Push notifications authorised")
            } else {
                self?.log.info("Push notifications denied by user")
            }
        }

        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("Device token: \(token.prefix(12))...")

        guard let api = apiClient else { return }
        Task {
            do {
                try await api.updateDeviceToken(token)
                log.info("Device token registered with server")
            } catch {
                log.error("Failed to register device token: \(error.localizedDescription)")
            }
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        log.error("Remote notification registration failed: \(error.localizedDescription)")
    }

    // MARK: - Categories

    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_TAPE",
            title: "View Tape",
            options: [.foreground]
        )

        let shareCategory = UNNotificationCategory(
            identifier: "TAPE_SHARE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let inviteCategory = UNNotificationCategory(
            identifier: "TAPE_INVITE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([shareCategory, inviteCategory])
    }

    // MARK: - Payload Handling

    private func handleNotificationPayload(_ userInfo: [AnyHashable: Any]) {
        guard let shareId = userInfo["share_id"] as? String else {
            log.warning("Push notification missing share_id")
            return
        }

        log.info("Handling push for share: \(shareId)")

        guard let api = apiClient, let nav = navigationCoordinator else {
            log.warning("API client or nav coordinator not available")
            return
        }

        Task { @MainActor in
            nav.handleShareLink(shareId: shareId, api: api)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        handleNotificationPayload(userInfo)
        completionHandler()
    }
}
