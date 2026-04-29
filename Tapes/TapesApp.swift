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
    @StateObject private var musicPreviewManager = MusicPreviewManager()

    private let apiClient = TapesAPIClient()

    init() {
        cleanupTempImports()
        Self.migrateMubertTracksToApplicationSupport()
        Self.cleanupLegacyMockMusicTracks()
        Task.detached(priority: .utility) { Self.applyMediaFileProtection() }
        if #available(iOS 26, *) {
            ExportCoordinator.registerBackgroundExportHandler()
            ShareUploadCoordinator.registerBackgroundUploadHandler()
            SharedTapeDownloadCoordinator.registerBackgroundDownloadHandler()
            CollabSyncCoordinator.registerBackgroundSyncHandler()
        }
    }

    /// One-shot cleanup for sine-wave WAV files that the old Mubert 401
    /// fallback wrote with a `.mp3` extension. Runs once per device,
    /// against the legacy `Caches/mubert_tracks/` location only.
    /// New installs / fresh users have nothing to clean.
    private static func cleanupLegacyMockMusicTracks() {
        let defaults = UserDefaults.standard
        let flagKey = "tapes_cleaned_mock_music_v1"
        guard !defaults.bool(forKey: flagKey) else { return }

        let legacyDir = MubertAPIClient.legacyTrackCacheDir()
        try? FileManager.default.removeItem(at: legacyDir)
        defaults.set(true, forKey: flagKey)
    }

    /// One-shot migration that moves any per-tape audio files from the
    /// old `Caches/mubert_tracks/` location into the durable
    /// `Application Support/mubert_tracks/`. Runs before mock cleanup
    /// so users who chose a legitimate library / prompt track in the
    /// old build don't lose it on first launch of this build.
    private static func migrateMubertTracksToApplicationSupport() {
        let defaults = UserDefaults.standard
        let flagKey = "tapes_migrated_mubert_to_app_support_v1"
        guard !defaults.bool(forKey: flagKey) else { return }

        let fm = FileManager.default
        let legacyDir = MubertAPIClient.legacyTrackCacheDir()
        guard fm.fileExists(atPath: legacyDir.path) else {
            defaults.set(true, forKey: flagKey)
            return
        }

        let destDir = MubertAPIClient.trackStorageDir()
        do {
            if !fm.fileExists(atPath: destDir.path) {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var dirURL = destDir
            try? dirURL.setResourceValues(values)

            let contents = (try? fm.contentsOfDirectory(atPath: legacyDir.path)) ?? []
            for name in contents where name.hasSuffix(".mp3") {
                let src = legacyDir.appendingPathComponent(name)
                let dst = destDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dst.path) { continue }
                try? fm.moveItem(at: src, to: dst)
            }
        } catch {
            // Migration is best-effort. If it fails the user simply
            // re-selects the track on the next "Use this track" tap.
        }

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
                .environmentObject(musicPreviewManager)
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
                    navigationCoordinator.apiClient = apiClient
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

    /// Single entry point for all deep links — universal links (shared tapes,
    /// reset password) and the `tapes://` custom scheme (verified email,
    /// shared tape fallback). One `.onOpenURL` is the Apple-recommended
    /// shape; nesting handlers across the view tree has undocumented
    /// resolution behaviour and silently drops links in some configurations.
    private func handleIncomingURL(_ url: URL) {
        if url.scheme == "tapes" && url.host == "verified" {
            authManager.markEmailVerified()
            return
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.path.contains("reset-password"),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            navigationCoordinator.pendingResetToken = token
            return
        }

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
