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
        if #available(iOS 26, *) {
            ExportCoordinator.registerBackgroundExportHandler()
        }
    }

    @AppStorage("tapes_appearance_mode") private var appearanceMode: AppearanceMode = .dark

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
                    PushNotificationManager.shared.navigationCoordinator = navigationCoordinator
                    PushNotificationManager.shared.requestAuthorisation()
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.pathExtension == "tape" {
            handleTapeFile(url)
            return
        }

        if let shareId = Self.shareId(from: url) {
            navigationCoordinator.handleShareLink(shareId: shareId, api: apiClient)
        }
    }

    /// `tapes://t/{id}` or `https://…/t/{id}` (Universal Link).
    private static func shareId(from url: URL) -> String? {
        if url.scheme?.lowercased() == "tapes", url.host == "t" {
            let p = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return p.isEmpty ? nil : p
        }
        if url.scheme == "http" || url.scheme == "https" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 2, parts[0] == "t" else { return nil }
            let id = parts[1]
            return id.isEmpty ? nil : id
        }
        return nil
    }

    private func handleTapeFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(TapeManifest.self, from: data)

            navigationCoordinator.navigateToSharedTape(tapeId: manifest.tapeId)
        } catch {
            // File couldn't be parsed — ignore silently
        }
    }
}
