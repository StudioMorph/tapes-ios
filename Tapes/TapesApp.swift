import SwiftUI
import BackgroundTasks

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
                    handleDeepLink(url)
                }
                .task {
                    authManager.apiClient = apiClient
                    PushNotificationManager.shared.apiClient = apiClient
                    PushNotificationManager.shared.navigationCoordinator = navigationCoordinator
                    PushNotificationManager.shared.requestAuthorisation()
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.pathExtension == "tape" {
            handleTapeFile(url)
            return
        }

        guard url.scheme == "tapes",
              url.host == "t",
              let shareId = url.pathComponents.last,
              !shareId.isEmpty else { return }

        navigationCoordinator.handleShareLink(shareId: shareId, api: apiClient)
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
