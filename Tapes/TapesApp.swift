import SwiftUI
import BackgroundTasks

@main
struct TapesApp: App {
    @StateObject private var tapeStore = TapesStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var entitlementManager = EntitlementManager()

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
                .preferredColorScheme(appearanceMode.colorScheme)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    authManager.apiClient = apiClient
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "tapes",
              url.host == "t",
              let shareId = url.pathComponents.last,
              !shareId.isEmpty else { return }

        Task {
            do {
                let resolution = try await apiClient.resolveShare(shareId: shareId)
                await MainActor.run {
                    // TODO: Navigate to the shared tape view with resolution.tapeId
                    _ = resolution
                }
            } catch {
                await MainActor.run {
                    authManager.authError = error.localizedDescription
                }
            }
        }
    }
}
