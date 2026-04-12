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
        guard url.scheme == "tapes",
              url.host == "t",
              let shareId = url.pathComponents.last,
              !shareId.isEmpty else { return }

        navigationCoordinator.handleShareLink(shareId: shareId, api: apiClient)
    }
}
