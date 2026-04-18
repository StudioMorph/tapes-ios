import SwiftUI

struct MainTabView: View {
    @Binding var showOnboarding: Bool
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var shareUploadCoordinator = ShareUploadCoordinator()
    @StateObject private var syncChecker = TapeSyncChecker()

    enum AppTab: Hashable {
        case myTapes
        case shared
        case account
    }

    var body: some View {
        TabView(selection: $navigationCoordinator.selectedTab) {
            Tab("My Tapes", systemImage: "film.stack", value: AppTab.myTapes) {
                TapesListView()
            }

            Tab("Shared", systemImage: "person.2", value: AppTab.shared) {
                SharedTapesView()
            }

            Tab("Account", systemImage: "person.circle", value: AppTab.account) {
                AccountTabView(showOnboarding: $showOnboarding)
            }
        }
        .tint(Tokens.Colors.systemBlue)
        .environmentObject(shareUploadCoordinator)
        .environmentObject(syncChecker)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let api = authManager.apiClient {
                syncChecker.checkAll(tapes: tapesStore.tapes, api: api)
            }
        }
    }
}

#Preview {
    MainTabView(showOnboarding: .constant(false))
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
        .environmentObject(NavigationCoordinator())
        .environmentObject(ShareUploadCoordinator())
}
