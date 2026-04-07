import SwiftUI
import BackgroundTasks

@main
struct TapesApp: App {
    @StateObject private var tapeStore = TapesStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var entitlementManager = EntitlementManager()

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
        }
    }
}
