import SwiftUI
import BackgroundTasks
import Foundation

@main
struct TapesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var tapeStore = TapesStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var entitlementManager = EntitlementManager()
    @StateObject private var navigationCoordinator = NavigationCoordinator()

    private let apiClient = TapesAPIClient()

    init() {
        cleanupTempImports()
        Self.cleanupLegacyMockMusicTracks()
        Task.detached(priority: .utility) { Self.applyMediaFileProtection() }
        BackgroundTransferManager.shared.reconnect()
        if #available(iOS 26, *) {
            ExportCoordinator.registerBackgroundExportHandler()
            ShareUploadCoordinator.registerBackgroundUploadHandler()
            SharedTapeDownloadCoordinator.registerBackgroundDownloadHandler()
            CollabSyncCoordinator.registerBackgroundSyncHandler()
        }
    }

    /// One-shot cleanup for sine-wave WAV files that the old Mubert 401
    /// fallback wrote with a `.mp3` extension. Runs once per device.
    private static func cleanupLegacyMockMusicTracks() {
        let defaults = UserDefaults.standard
        let flagKey = "tapes_cleaned_mock_music_v1"
        guard !defaults.bool(forKey: flagKey) else { return }

        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mubert_tracks", isDirectory: true)

        try? FileManager.default.removeItem(at: cacheDir)
        defaults.set(true, forKey: flagKey)
    }

    /// Applies `.completeUntilFirstUserAuthentication` to `tapes.json` and the
    /// `clip_media/` directory plus its contents. Runs once per device. New
    /// writes from `TapePersistenceActor` also set this class explicitly.
    private static func applyMediaFileProtection() {
        let defaults = UserDefaults.standard
        let flagKey = "tapes_applied_file_protection_v1"
        guard !defaults.bool(forKey: flagKey) else { return }

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let mediaDir = docs.appendingPathComponent("clip_media", isDirectory: true)
        let tapesJson = docs.appendingPathComponent("tapes.json")

        let attrs: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]

        try? fm.setAttributes(attrs, ofItemAtPath: docs.path)
        if fm.fileExists(atPath: mediaDir.path) {
            try? fm.setAttributes(attrs, ofItemAtPath: mediaDir.path)
            if let contents = try? fm.contentsOfDirectory(atPath: mediaDir.path) {
                for file in contents {
                    let path = mediaDir.appendingPathComponent(file).path
                    try? fm.setAttributes(attrs, ofItemAtPath: path)
                }
            }
        }
        if fm.fileExists(atPath: tapesJson.path) {
            try? fm.setAttributes(attrs, ofItemAtPath: tapesJson.path)
        }

        defaults.set(true, forKey: flagKey)
    }

    @AppStorage("tapes_appearance_mode") private var appearanceMode: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tapeStore)
                .environmentObject(authManager)
                .environmentObject(entitlementManager)
                .environmentObject(navigationCoordinator)
                .preferredColorScheme(appearanceMode.colorScheme)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    handleIncomingURL(url)
                }
                .task {
                    authManager.apiClient = apiClient
                    PushNotificationManager.shared.apiClient = apiClient
                    PushNotificationManager.shared.authManager = authManager
                    PushNotificationManager.shared.navigationCoordinator = navigationCoordinator
                    PushNotificationManager.shared.requestAuthorisation()

                    AdManager.shared.preWarm()

                    if authManager.isSignedIn {
                        await authManager.refreshProfile()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    requestAdConsent()
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if let shareId = Self.shareId(from: url) {
            navigationCoordinator.handleShareLink(shareId: shareId)
        }
    }

    private func requestAdConsent() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController
        else { return }
        ConsentManager.shared.requestConsentIfNeeded(from: rootVC)
    }

    /// `tapes://t/{id}` or `https://…/t/{id}` (Universal Link).
    private static func shareId(from url: URL) -> String? {
        if url.scheme?.lowercased() == "tapes", url.host == "t" {
            let p = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return p.isEmpty ? nil : p
        }
        if url.scheme == "http" || url.scheme == "https" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.hasPrefix("t/reset-password") { return nil }
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 2, parts[0] == "t" else { return nil }
            let id = parts[1]
            return id.isEmpty ? nil : id
        }
        return nil
    }
}
