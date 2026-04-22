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
                        guard item.status == "invited", !alreadyLocal, !alreadyPending,
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

    // MARK: - Floating Clip Overlay

    @ViewBuilder
    private func floatingClipOverlay(clip: Clip, containerOrigin: CGPoint) -> some View {
        let size = tapesStore.floatingThumbSize
        let isHovering = hoveredTarget != nil
        let displayScale: CGFloat = isHovering ? 0.5 : 1.0
        let localPos = CGPoint(
            x: tapesStore.floatingPosition.x - containerOrigin.x,
            y: tapesStore.floatingPosition.y - containerOrigin.y
        )

        ZStack {
            if let thumbnail = clip.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Tokens.Colors.tertiaryBackground)
                    .frame(width: size.width, height: size.height)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    tapesStore.returnFloatingClip()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Tokens.Colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .offset(x: 12, y: -12)
        }
        .scaleEffect(displayScale)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovering)
        .position(localPos)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    tapesStore.floatingPosition = value.location
                }
                .onEnded { value in
                    let target = dropTargets.first {
                        $0.frame.contains(value.location) && $0.tapeID == tapesStore.jigglingTapeID
                    }
                    if let target {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            tapesStore.dropFloatingClip(onTape: target.tapeID, atIndex: target.insertionIndex, afterClipID: target.seamLeftClipID, beforeClipID: target.seamRightClipID)
                        }
                    }
                    hoveredTarget = nil
                }
        )
        .zIndex(999)
    }

    private func updateHoverTarget(at location: CGPoint) {
        let newTarget = dropTargets.first {
            $0.frame.contains(location) && $0.tapeID == tapesStore.jigglingTapeID
        }
        if newTarget != hoveredTarget {
            if newTarget != nil {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
            hoveredTarget = newTarget
        }
    }

    enum AppTab: Hashable {
        case myTapes
        case shared
        case collab
        case account
    }

    @State private var dropTargets: [DropTargetInfo] = []
    @State private var hoveredTarget: DropTargetInfo? = nil

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
        .onPreferenceChange(DropTargetPreferenceKey.self) { targets in
            dropTargets = targets
        }
        .overlay {
            if let clip = tapesStore.floatingClip {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    floatingClipOverlay(clip: clip, containerOrigin: origin)
                }
                .ignoresSafeArea()
                .allowsHitTesting(true)
            }
        }
        .onChange(of: tapesStore.floatingPosition) { _, newPos in
            guard tapesStore.isFloatingClip else { return }
            updateHoverTarget(at: newPos)
        }
        .onChange(of: tapesStore.floatingDragDidEnd) { _, didEnd in
            guard didEnd, tapesStore.isFloatingClip else { return }
            tapesStore.isFloatingDragActive = false
            let location = tapesStore.floatingPosition
            let target = dropTargets.first {
                $0.frame.contains(location) && $0.tapeID == tapesStore.jigglingTapeID
            }
            if let target {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tapesStore.dropFloatingClip(onTape: target.tapeID, atIndex: target.insertionIndex, afterClipID: target.seamLeftClipID, beforeClipID: target.seamRightClipID)
                }
            }
            hoveredTarget = nil
            tapesStore.floatingDragDidEnd = false
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
