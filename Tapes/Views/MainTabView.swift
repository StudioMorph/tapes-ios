import Combine
import SwiftUI
import UserNotifications

struct MainTabView: View {
    @Binding var showOnboarding: Bool
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var shareUploadCoordinator = ShareUploadCoordinator()
    @StateObject private var syncChecker = TapeSyncChecker()

    private var viewOnlyDownloadCount: Int {
        guard !syncChecker.pendingDownloads.isEmpty else { return 0 }
        var count = 0
        for tape in tapesStore.tapes where tape.isShared && !tape.isCollabTape {
            if (tape.shareInfo?.mode ?? "view_only") == "view_only",
               syncChecker.pendingDownloads[tape.id] != nil {
                count += 1
            }
        }
        return count
    }

    private var collabDownloadCount: Int {
        guard !syncChecker.pendingDownloads.isEmpty else { return 0 }
        var count = 0
        for tape in tapesStore.tapes {
            let isCollab = tape.isCollabTape || (tape.isShared && tape.shareInfo?.mode == "collaborative")
            if isCollab, syncChecker.pendingDownloads[tape.id] != nil {
                count += 1
            }
        }
        return count
    }

    enum AppTab: Hashable {
        case myTapes
        case shared
        case collab
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
            .badge(viewOnlyDownloadCount)

            Tab("Collab", systemImage: "person.2.wave.2", value: AppTab.collab) {
                CollabTapesView()
            }
            .badge(collabDownloadCount)

            Tab("Account", systemImage: "person.circle", value: AppTab.account) {
                AccountTabView(showOnboarding: $showOnboarding)
            }
        }
        .tint(Tokens.Colors.systemBlue)
        .environmentObject(shareUploadCoordinator)
        .environmentObject(syncChecker)
        .task {
            PushNotificationManager.shared.syncChecker = syncChecker
            PushNotificationManager.shared.tapesProvider = { [weak tapesStore] in
                tapesStore?.tapes ?? []
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let api = authManager.apiClient {
                syncChecker.checkAll(tapes: tapesStore.tapes, api: api)
            }
        }
        .onReceive(Timer.publish(every: TapeSyncChecker.checkInterval, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active, let api = authManager.apiClient else { return }
            syncChecker.checkAll(tapes: tapesStore.tapes, api: api)
        }
        .onChange(of: navigationCoordinator.selectedTab) { _, tab in
            if tab == .shared || tab == .collab {
                UNUserNotificationCenter.current().setBadgeCount(0)
            }
            if tapesStore.jigglingTapeID != nil {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if tapesStore.isFloatingClip {
                        tapesStore.returnFloatingClip()
                    }
                    tapesStore.jigglingTapeID = nil
                }
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
