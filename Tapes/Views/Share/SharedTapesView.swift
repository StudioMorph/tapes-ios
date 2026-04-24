import SwiftUI

struct SharedTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var downloadCoordinator = SharedTapeDownloadCoordinator()
    @StateObject private var importCoordinator = MediaImportCoordinator()
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @EnvironmentObject private var syncChecker: TapeSyncChecker
    @EnvironmentObject private var pendingInviteStore: PendingInviteStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var tapeToPreview: Tape?
    @State private var tapeToShare: Tape?
    @State private var tapeToSettings: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""
    @State private var inviteToDismiss: PendingInvite?
    @State private var sortedTapeIDs: [UUID] = []

    private var viewOnlyTapes: [Tape] {
        let tapes = tapesStore.tapes
            .filter { $0.isShared && !$0.isCollabTape && ($0.shareInfo?.mode ?? "view_only") == "view_only" }
        if sortedTapeIDs.isEmpty { return tapes }
        let lookup = Dictionary(uniqueKeysWithValues: tapes.map { ($0.id, $0) })
        var ordered = sortedTapeIDs.compactMap { lookup[$0] }
        let newTapes = tapes.filter { !sortedTapeIDs.contains($0.id) }
        ordered.insert(contentsOf: newTapes, at: 0)
        return ordered
    }

    private func refreshSortOrder() {
        let sorted = tapesStore.tapes
            .filter { $0.isShared && !$0.isCollabTape && ($0.shareInfo?.mode ?? "view_only") == "view_only" }
            .sorted { a, b in
                let aHas = syncChecker.pendingDownloads[a.id] != nil
                let bHas = syncChecker.pendingDownloads[b.id] != nil
                if aHas != bHas { return aHas }
                return a.updatedAt > b.updatedAt
            }
        sortedTapeIDs = sorted.map(\.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)

                if !authManager.isSignedIn {
                    signInPrompt
                } else if !authManager.isEmailVerified {
                    unverifiedBanner
                } else if viewOnlyTapes.isEmpty && pendingInviteStore.viewOnlyInvites.isEmpty {
                    emptyState
                } else {
                    sharedTapeList
                }

                SharedDownloadProgressOverlay(coordinator: downloadCoordinator)

                if let invite = inviteToDismiss {
                    dismissConfirmationOverlay(invite: invite)
                }
            }
            .navigationTitle("Shared")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if tapesStore.jigglingTapeID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if tapesStore.isFloatingClip {
                                    tapesStore.returnFloatingClip()
                                }
                                tapesStore.jigglingTapeID = nil
                            }
                        }
                        .font(.body.weight(.semibold))
                    }
                } else {
                    if downloadCoordinator.isDownloading && !downloadCoordinator.showProgressDialog {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                downloadCoordinator.showProgressDialogAgain()
                            } label: {
                                ZStack {
                                    CircularProgressRing(
                                        progress: downloadCoordinator.progress,
                                        lineWidth: 2.5,
                                        size: 22,
                                        ringColor: .blue
                                    )
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                    }
                }
            }
            .alert("Sign In Issue", isPresented: .init(
                get: { authManager.authError != nil },
                set: { if !$0 { authManager.authError = nil } }
            )) {
                Button("OK") { authManager.authError = nil }
            } message: {
                if let msg = authManager.authError {
                    Text(msg)
                }
            }
            .alert("Download Failed", isPresented: .init(
                get: { downloadCoordinator.downloadError != nil },
                set: { if !$0 { downloadCoordinator.downloadError = nil } }
            )) {
                Button("OK") { downloadCoordinator.downloadError = nil }
            } message: {
                if let msg = downloadCoordinator.downloadError {
                    Text(msg)
                }
            }
            .onChange(of: navigationCoordinator.pendingSharedTapeId) { _, newId in
                if let shareId = newId {
                    navigationCoordinator.clearPendingTape()
                    handleIncomingShare(shareId: shareId)
                }
            }
            .onAppear {
                refreshSortOrder()
                if let shareId = navigationCoordinator.pendingSharedTapeId {
                    navigationCoordinator.clearPendingTape()
                    handleIncomingShare(shareId: shareId)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                downloadCoordinator.handleScenePhaseChange(newPhase)
            }
            .onChange(of: downloadCoordinator.resolvedMode) { _, mode in
                if mode == "collaborative" {
                    navigationCoordinator.pendingCollabSegment = "contributingTo"
                    navigationCoordinator.selectedTab = .collab
                }
            }
            .onChange(of: downloadCoordinator.resultTape?.id) { _, newId in
                guard newId != nil,
                      let tape = downloadCoordinator.resultTape else { return }

                if let remoteTapeId = tape.shareInfo?.remoteTapeId {
                    pendingInviteStore.remove(tapeId: remoteTapeId)
                }
            }
        }
        .environmentObject(importCoordinator)
        .sheet(item: $tapeToShare) { shareTape in
            if let binding = tapesStore.bindingForTape(id: shareTape.id) {
                ShareModalView(tape: binding, pendingMergeTape: .constant(nil))
            }
        }
        .sheet(item: $tapeToSettings) { settingsTape in
            if let binding = tapesStore.bindingForTape(id: settingsTape.id) {
                TapeSettingsView(
                    tape: binding,
                    onDismiss: { tapeToSettings = nil },
                    onTapeDeleted: { tapeToSettings = nil }
                )
            }
        }
        .fullScreenCover(item: $tapeToPreview) { tape in
            TapePlayerView(tape: tape, onDismiss: {
                tapeToPreview = nil
            }, onSave: { updatedTape in
                tapesStore.updateTape(updatedTape)
            })
        }
        .fullScreenCover(isPresented: $cameraCoordinator.isPresented) {
            CameraView(coordinator: cameraCoordinator)
                .ignoresSafeArea(.all, edges: .all)
        }
    }

    // MARK: - Shared Tape List

    private var sharedTapeList: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - (Tokens.Spacing.m * 2)

            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.m) {
                    ForEach(pendingInviteStore.viewOnlyInvites) { invite in
                        PendingInviteCard(
                            invite: invite,
                            onLoad: { handleLoadInvite(invite) },
                            onDismiss: { inviteToDismiss = invite }
                        )
                    }

                    ForEach(viewOnlyTapes) { tape in
                        if let binding = tapesStore.bindingForTape(id: tape.id) {
                            let tapeID = tape.id

                            let titleConfig: TapeCardView.TitleEditingConfig? = {
                                guard editingTapeID == tapeID else { return nil }
                                return TapeCardView.TitleEditingConfig(
                                    text: Binding(
                                        get: { draftTitle },
                                        set: { draftTitle = $0 }
                                    ),
                                    tapeID: tapeID,
                                    onCommit: { commitTitleEdit() }
                                )
                            }()

                            TapeCardView(
                                tape: binding,
                                tapeID: tapeID,
                                tapeWidth: contentWidth,
                                isLandscape: false,
                                isShareDisabled: true,
                                onShare: { tapeToShare = tape },
                                onSettings: { tapeToSettings = tape },
                                onPlay: {
                                    tapesStore.clearUnseenContent(for: tape.id)
                                    var cleared = tape
                                    cleared.hasUnseenContent = false
                                    tapeToPreview = cleared
                                },
                                onThumbnailDelete: { _ in },
                                onCameraCapture: { completion in
                                    cameraCoordinator.presentCamera(completion: completion)
                                },
                                onTitleFocusRequest: {
                                    editingTapeID = tapeID
                                    draftTitle = tape.title
                                },
                                titleEditingConfig: titleConfig
                            )
                            .background(Tokens.Colors.primaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            .overlay(alignment: .bottomTrailing) {
                                if let count = syncChecker.pendingDownloads[tapeID], count > 0, !downloadCoordinator.isDownloading, tapesStore.jigglingTapeID == nil {
                                    SyncBadge(count: count, direction: .download) {
                                        handleDownload(tape: tape)
                                    }
                                }
                            }
                            .compositingGroup()
                            .opacity(tapesStore.jigglingTapeID != nil && tapesStore.jigglingTapeID != tapeID ? 0.4 : 1)
                            .disabled(tapesStore.jigglingTapeID != nil && tapesStore.jigglingTapeID != tapeID)
                            .animation(.easeInOut(duration: 0.25), value: tapesStore.jigglingTapeID)
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.s)
            }
            .scrollDisabled(tapesStore.isFloatingDragActive)
        }
    }

    // MARK: - Sign In Prompt

    private var signInPrompt: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text("Sign in to see shared tapes")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("Tapes shared with you will appear here after you sign in.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Unverified Banner

    private var unverifiedBanner: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("Verify your email")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("Verify your email to share and collaborate on tapes.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            Button("Resend Verification Email") {
                Task { await authManager.resendVerification() }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text("No shared tapes yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("When someone shares a tape with you, it will appear here.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Title Editing

    private func commitTitleEdit() {
        guard let tapeID = editingTapeID else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, var tape = tapesStore.tapes.first(where: { $0.id == tapeID }) {
            tape.title = trimmed
            tapesStore.updateTape(tape)
        }
        editingTapeID = nil
        draftTitle = ""
    }

    // MARK: - Handle Incoming Share

    private func handleIncomingShare(shareId: String) {
        guard let api = authManager.apiClient else {
            downloadCoordinator.downloadError = "Please sign in first to receive shared tapes."
            return
        }
        downloadCoordinator.startDownload(
            shareId: shareId,
            api: api,
            tapeStore: tapesStore
        )
    }

    // MARK: - Handle Load Invite

    private func handleLoadInvite(_ invite: PendingInvite) {
        pendingInviteStore.remove(tapeId: invite.tapeId)
        handleIncomingShare(shareId: invite.shareId)
    }

    // MARK: - Dismiss Confirmation

    @ViewBuilder
    private func dismissConfirmationOverlay(invite: PendingInvite) -> some View {
        GlassAlertCard(
            title: "Dismiss Shared Tape?",
            buttons: [
                GlassAlertButton(title: "Cancel", style: .secondary) {
                    withAnimation { inviteToDismiss = nil }
                },
                GlassAlertButton(title: "Dismiss", style: .destructive) {
                    withAnimation { inviteToDismiss = nil }
                    pendingInviteStore.remove(tapeId: invite.tapeId)
                    if let api = authManager.apiClient {
                        Task { try? await api.declineInvite(tapeId: invite.tapeId) }
                    }
                },
            ],
            icon: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.systemRed)
            },
            message: {
                Text("This tape will be removed. The only way to get it back is to ask the owner to share it with you again.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
        )
    }

    // MARK: - Handle Badge Download

    private func handleDownload(tape: Tape) {
        guard let shareId = tape.shareInfo?.shareId,
              let api = authManager.apiClient else { return }
        syncChecker.clearDownload(for: tape.id)
        downloadCoordinator.startDownload(
            shareId: shareId,
            api: api,
            tapeStore: tapesStore
        )
    }
}

#Preview {
    SharedTapesView()
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
        .environmentObject(NavigationCoordinator())
        .environmentObject(ShareUploadCoordinator())
        .environmentObject(TapeSyncChecker())
        .environmentObject(PendingInviteStore())
}
