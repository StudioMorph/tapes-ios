import UIKit
import UserNotifications
import os

final class PushNotificationManager: NSObject, ObservableObject {

    static let shared = PushNotificationManager()

    var apiClient: TapesAPIClient?
    var authManager: AuthManager?
    var navigationCoordinator: NavigationCoordinator?
    var syncChecker: TapeSyncChecker?
    var tapesProvider: (() -> [Tape])?
    var pendingInviteStore: PendingInviteStore?

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

    // MARK: - Background Push (content-available)

    func handleBackgroundPush(
        userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let action = userInfo["action"] as? String
        let remoteTapeId = userInfo["tape_id"] as? String

        log.info("[BackgroundPush] action=\(action ?? "none") tape=\(remoteTapeId ?? "none")")

        if action == "email_verified" {
            Task { @MainActor in
                self.authManager?.markEmailVerified()
                self.log.info("[BackgroundPush] email verified via silent push")
                completionHandler(.newData)
            }
            return
        }

        if action == "tape_invite" {
            Task { @MainActor in
                self.handleInvitePush(userInfo: userInfo)
                completionHandler(.newData)
            }
            return
        }

        guard let api = apiClient,
              let checker = syncChecker,
              let tapes = tapesProvider?() else {
            log.warning("[BackgroundPush] dependencies not ready, skipping")
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            if let remoteTapeId {
                await checker.updateFromPushAndWait(remoteTapeId: remoteTapeId, tapes: tapes, api: api)
            } else {
                await checker.refreshAndWait(tapes: tapes, api: api)
            }
            completionHandler(.newData)
        }
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

        let expiryCategory = UNNotificationCategory(
            identifier: "TAPE_EXPIRY_WARNING",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let digestCategory = UNNotificationCategory(
            identifier: "TAPE_DIGEST",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            shareCategory, inviteCategory, expiryCategory, digestCategory
        ])
    }

    // MARK: - Invite Push Handling

    @MainActor
    private func handleInvitePush(userInfo: [AnyHashable: Any]) {
        guard let tapeId = userInfo["tape_id"] as? String,
              let title = userInfo["tape_title"] as? String,
              let ownerName = userInfo["owner_name"] as? String,
              let shareId = userInfo["share_id"] as? String,
              let mode = userInfo["mode"] as? String else {
            log.warning("[InvitePush] missing required fields in payload")
            return
        }

        let invite = PendingInvite(
            tapeId: tapeId,
            title: title,
            ownerName: ownerName,
            shareId: shareId,
            mode: mode,
            receivedAt: Date()
        )

        pendingInviteStore?.add(invite)
        log.info("[InvitePush] persisted invite for '\(title)' from \(ownerName)")
    }

    // MARK: - Payload Handling (user tapped notification)

    private func handleNotificationPayload(_ userInfo: [AnyHashable: Any]) {
        guard let nav = navigationCoordinator else {
            log.warning("Navigation coordinator not available")
            return
        }

        if let shareId = userInfo["share_id"] as? String, !shareId.isEmpty {
            log.info("Handling push for share: \(shareId)")
            Task { @MainActor in
                nav.handleShareLink(shareId: shareId)
            }
            return
        }

        if userInfo["tape_id"] != nil {
            log.info("Handling push with tape_id — navigating to Shared tab")
            Task { @MainActor in
                nav.selectedTab = .shared
            }
            return
        }

        log.warning("Push notification missing both tape_id and share_id")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let action = userInfo["action"] as? String

        if action == "email_verified" {
            Task { @MainActor in
                self.authManager?.markEmailVerified()
                self.log.info("[ForegroundPush] email verified via silent push")
            }
            completionHandler([])
            return
        } else if action == "tape_invite" {
            Task { @MainActor in
                self.handleInvitePush(userInfo: userInfo)
            }
        } else if action == "sync_update",
                  let api = apiClient,
                  let checker = syncChecker,
                  let tapes = tapesProvider?() {
            Task { @MainActor in
                if let remoteTapeId = userInfo["tape_id"] as? String {
                    checker.updateFromPush(remoteTapeId: remoteTapeId, tapes: tapes, api: api)
                }
            }
        }
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
