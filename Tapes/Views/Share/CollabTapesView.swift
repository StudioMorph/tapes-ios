import SwiftUI
import AuthenticationServices

struct CollabTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @StateObject private var downloadCoordinator = SharedTapeDownloadCoordinator()
    @StateObject private var syncCoordinator = CollabSyncCoordinator()
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

    private var ownerCollabTapes: [Tape] {
        tapesStore.tapes
            .filter { $0.isCollabTape }
            .sorted { a, b in
                let aEmpty = a.clips.isEmpty && !a.hasReceivedFirstContent
                let bEmpty = b.clips.isEmpty && !b.hasReceivedFirstContent
                if aEmpty != bEmpty { return aEmpty }

                let aHasSync = syncCount(for: a) > 0
                let bHasSync = syncCount(for: b) > 0
                if aHasSync != bHasSync { return aHasSync }

                return a.updatedAt > b.updatedAt
            }
    }

    private var receivedCollabTapes: [Tape] {
        tapesStore.tapes
            .filter { !$0.isCollabTape && $0.isShared && $0.shareInfo?.mode == "collaborative" }
            .sorted { a, b in
                let aHasSync = syncCount(for: a) > 0
                let bHasSync = syncCount(for: b) > 0
                if aHasSync != bHasSync { return aHasSync }
                return a.updatedAt > b.updatedAt
            }
    }

    /// True when the upload coordinator is working on a tape owned by this tab.
    private var isCollabUpload: Bool {
        guard let source = uploadCoordinator.sourceTape else { return false }
        return source.isCollabTape || source.shareInfo?.mode == "collaborative"
    }

    /// Computes the total pending sync items for a collab tape (uploads + downloads).
    /// Upload count is computed reactively from the tape model, not from TapeSyncChecker.
    private func syncCount(for tape: Tape) -> Int {
        let downloads = syncChecker.pendingDownloads[tape.id] ?? 0
        let uploads: Int
        if tape.isCollabTape {
            uploads = tape.pendingUploadCount
        } else {
            uploads = tape.clips.filter { !$0.isPlaceholder && !$0.isSynced }.count
        }
        return downloads + uploads
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)

                if !authManager.isSignedIn {
                    signInPrompt
                } else {
                    collabTapeList
                }

                dialogOverlays
            }
            .navigationTitle("Collab")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
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
            .onChange(of: scenePhase) { _, newPhase in
                downloadCoordinator.handleScenePhaseChange(newPhase)
                syncCoordinator.handleScenePhaseChange(newPhase)
            }
            .onChange(of: uploadCoordinator.lastUploadedClipCount) { _, count in
                guard let count,
                      let source = uploadCoordinator.sourceTape,
                      source.isCollabTape else { return }
                tapesStore.setLastUploadedClipCount(count, for: source.id)
            }
            .onChange(of: uploadCoordinator.lastSyncedClipIds) { _, ids in
                guard !ids.isEmpty,
                      let source = uploadCoordinator.sourceTape,
                      source.isCollabTape else { return }
                for clipId in ids {
                    tapesStore.markClipSynced(clipId, inTape: source.id)
                }
            }
        }
        .environmentObject(importCoordinator)
        .sheet(item: $tapeToShare) { tape in
            ShareModalView(tape: tape)
        }
        .sheet(item: $tapeToSettings) { settingsTape in
            if let binding = tapesStore.bindingForTape(id: settingsTape.id) {
                TapeSettingsView(
                    tape: binding,
                    onDismiss: { tapeToSettings = nil },
                    onTapeDeleted: { tapeToSettings = nil },
                    onMergeAndSave: { _ in }
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

    // MARK: - Overlays

    @ViewBuilder
    private var dialogOverlays: some View {
        if !syncCoordinator.isSyncing {
            SharedDownloadProgressOverlay(coordinator: downloadCoordinator, title: "Receiving Contributions…")
        }
        ImportProgressOverlay(coordinator: importCoordinator)

        if let invite = inviteToDismiss {
            dismissConfirmationOverlay(invite: invite)
        }

        syncDialogOverlays
        uploadDialogOverlays
    }

    @ViewBuilder
    private var syncDialogOverlays: some View {
        if syncCoordinator.isSyncing && syncCoordinator.showProgressDialog {
            CollabSyncProgressDialog(coordinator: syncCoordinator)
        }
        if syncCoordinator.showCompletionDialog {
            CollabSyncCompletionDialog(coordinator: syncCoordinator)
        }
        if syncCoordinator.syncError != nil && !syncCoordinator.isSyncing {
            CollabSyncErrorAlert(coordinator: syncCoordinator)
        }
    }

    @ViewBuilder
    private var uploadDialogOverlays: some View {
        if isCollabUpload && !syncCoordinator.isSyncing {
            if uploadCoordinator.showProgressDialog {
                ShareUploadProgressDialog(coordinator: uploadCoordinator)
            }
            if uploadCoordinator.showCompletionDialog {
                ShareUploadCompletionDialog(coordinator: uploadCoordinator)
            }
            if uploadCoordinator.uploadError != nil {
                ShareUploadErrorAlert(coordinator: uploadCoordinator)
            }
            if uploadCoordinator.showPostUploadDialog {
                SharePostUploadDialog(coordinator: uploadCoordinator)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if tapesStore.jigglingTapeID != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        tapesStore.jigglingTapeID = nil
                    }
                }
                .font(.body.weight(.semibold))
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                backgroundProgressButton
            }
        }
    }

    @ViewBuilder
    private var backgroundProgressButton: some View {
        if syncCoordinator.isSyncing && !syncCoordinator.showProgressDialog {
            progressRingButton(
                progress: syncCoordinator.progress,
                icon: "arrow.triangle.2.circlepath",
                iconSize: 10
            ) { syncCoordinator.showProgressDialogAgain() }
        } else if isCollabUpload && uploadCoordinator.isUploading && !uploadCoordinator.showProgressDialog {
            progressRingButton(
                progress: uploadCoordinator.progress,
                icon: "arrow.up",
                iconSize: 11
            ) { uploadCoordinator.showProgressDialogAgain() }
        } else if downloadCoordinator.isDownloading && !downloadCoordinator.showProgressDialog {
            progressRingButton(
                progress: downloadCoordinator.progress,
                icon: "arrow.down",
                iconSize: 11
            ) { downloadCoordinator.showProgressDialogAgain() }
        }
    }

    private func progressRingButton(
        progress: Double,
        icon: String,
        iconSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                CircularProgressRing(
                    progress: progress,
                    lineWidth: 2.5,
                    size: 22,
                    ringColor: .blue
                )
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
            }
        }
    }

    // MARK: - Collab Tape List

    private var collabTapeList: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - (Tokens.Spacing.m * 2)

            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.m) {
                    ForEach(ownerCollabTapes) { tape in
                        if let binding = tapesStore.bindingForTape(id: tape.id) {
                            collabTapeCard(tape: tape, binding: binding, width: contentWidth, isOwner: true)
                        }
                    }

                    if !pendingInviteStore.collaborativeInvites.isEmpty || !receivedCollabTapes.isEmpty {
                        Text("Collaborating")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Tokens.Spacing.s)

                        ForEach(pendingInviteStore.collaborativeInvites) { invite in
                            PendingInviteCard(
                                invite: invite,
                                onLoad: { handleLoadInvite(invite) },
                                onDismiss: { inviteToDismiss = invite }
                            )
                        }

                        ForEach(receivedCollabTapes) { tape in
                            if let binding = tapesStore.bindingForTape(id: tape.id) {
                                collabTapeCard(tape: tape, binding: binding, width: contentWidth, isOwner: false)
                            }
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.s)
            }
        }
    }

    @ViewBuilder
    private func collabTapeCard(tape: Tape, binding: Binding<Tape>, width: CGFloat, isOwner: Bool) -> some View {
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
            tapeWidth: width,
            isLandscape: false,
            isShareDisabled: false,
            onShare: { tapeToShare = tape },
            onSettings: { tapeToSettings = tape },
            onPlay: {
                tapesStore.clearUnseenContent(for: tape.id)
                var cleared = tape
                cleared.hasUnseenContent = false
                tapeToPreview = cleared
            },
            onThumbnailDelete: { clip in
                tapesStore.deleteClip(from: tapeID, clip: clip)
            },
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
            let total = syncCount(for: tape)
            if total > 0, tape.shareInfo != nil {
                SyncBadge(count: total, direction: .sync) {
                    handleSync(tape: tape)
                }
            }
        }
        .compositingGroup()
        .opacity(tapesStore.jigglingTapeID != nil && tapesStore.jigglingTapeID != tapeID ? 0.4 : 1)
        .disabled(tapesStore.jigglingTapeID != nil && tapesStore.jigglingTapeID != tapeID)
        .animation(.easeInOut(duration: 0.25), value: tapesStore.jigglingTapeID)
    }

    // MARK: - Sign In Prompt

    private var signInPrompt: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text("Sign in to collaborate")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("Create collaborative tapes and invite others to contribute.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                authManager.handleAuthorization(result)
            }
            .frame(height: Tokens.HitTarget.recommended)
            .clipShape(Capsule())
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

    // MARK: - Handle Load Invite

    private func handleLoadInvite(_ invite: PendingInvite) {
        guard let api = authManager.apiClient else { return }
        pendingInviteStore.remove(tapeId: invite.tapeId)
        downloadCoordinator.startDownload(
            shareId: invite.shareId,
            api: api,
            tapeStore: tapesStore
        )
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

    // MARK: - Handle Bidirectional Sync

    private func handleSync(tape: Tape) {
        guard let api = authManager.apiClient else { return }

        let hasUploads: Bool
        if tape.isCollabTape {
            hasUploads = tape.pendingUploadCount > 0
        } else {
            hasUploads = tape.clips.contains { !$0.isPlaceholder && !$0.isSynced }
        }
        let hasDownloads = (syncChecker.pendingDownloads[tape.id] ?? 0) > 0

        syncChecker.clearDownload(for: tape.id)

        if hasUploads && hasDownloads {
            syncCoordinator.startSync(
                tape: tape,
                hasUploads: true,
                hasDownloads: true,
                uploadCoordinator: uploadCoordinator,
                downloadCoordinator: downloadCoordinator,
                api: api,
                tapesStore: tapesStore,
                markClipsSynced: { syncedIds in
                    for clipId in syncedIds {
                        self.tapesStore.markClipSynced(clipId, inTape: tape.id)
                    }
                }
            )
        } else if hasUploads {
            if tape.isCollabTape {
                uploadCoordinator.ensureTapeUploaded(
                    tape: tape,
                    intendedForCollaboration: true,
                    api: api
                )
            } else {
                uploadCoordinator.contributeClips(tape: tape, api: api) { syncedIds in
                    for clipId in syncedIds {
                        self.tapesStore.markClipSynced(clipId, inTape: tape.id)
                    }
                }
            }
        } else if hasDownloads, let shareId = tape.shareInfo?.shareId {
            downloadCoordinator.startDownload(
                shareId: shareId,
                api: api,
                tapeStore: tapesStore
            )
        }
    }
}

#Preview {
    CollabTapesView()
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
        .environmentObject(NavigationCoordinator())
        .environmentObject(ShareUploadCoordinator())
        .environmentObject(TapeSyncChecker())
        .environmentObject(PendingInviteStore())
}
