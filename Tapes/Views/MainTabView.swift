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
    @StateObject private var pendingInviteStore = PendingInviteStore()

    private var viewOnlyDownloadCount: Int {
        var count = pendingInviteStore.viewOnlyInvites.count
        for tape in tapesStore.tapes where tape.isShared && !tape.isCollabTape {
            if (tape.shareInfo?.mode ?? "view_only") == "view_only",
               syncChecker.pendingDownloads[tape.id] != nil {
                count += 1
            }
        }
        return count
    }

    private var collabDownloadCount: Int {
        var count = pendingInviteStore.collaborativeInvites.count
        for tape in tapesStore.tapes {
            let isCollab = tape.isCollabTape || (tape.isShared && tape.shareInfo?.mode == "collaborative")
            if isCollab, syncChecker.pendingDownloads[tape.id] != nil {
                count += 1
            }
        }
        return count
    }

    /// Cold-start fallback: fetches tapes shared with the user from the server
    /// and creates pending invites for any not yet in the local store.
    private func catchUpMissedInvites(api: TapesAPIClient) {
        Task {
            do {
                let serverTapes = try await api.getSharedTapes()
                await MainActor.run {
                    for item in serverTapes {
                        let alreadyLocal = tapesStore.sharedTape(forRemoteId: item.tapeId) != nil
                        let alreadyPending = pendingInviteStore.contains(tapeId: item.tapeId)
                        guard !alreadyLocal, !alreadyPending,
                              let shareId = item.shareId else { continue }
                        pendingInviteStore.add(PendingInvite(
                            tapeId: item.tapeId,
                            title: item.title,
                            ownerName: item.ownerName,
                            shareId: shareId,
                            mode: item.mode,
                            receivedAt: item.sharedAt ?? Date()
                        ))
                    }
                }
            } catch {
                // Fallback is best-effort; don't surface errors.
            }
        }
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
        .environmentObject(pendingInviteStore)
        .task {
            PushNotificationManager.shared.syncChecker = syncChecker
            PushNotificationManager.shared.pendingInviteStore = pendingInviteStore
            PushNotificationManager.shared.tapesProvider = { [weak tapesStore] in
                tapesStore?.tapes ?? []
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let api = authManager.apiClient {
                syncChecker.checkAll(tapes: tapesStore.tapes, api: api)
                catchUpMissedInvites(api: api)
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
