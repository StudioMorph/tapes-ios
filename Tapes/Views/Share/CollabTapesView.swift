import SwiftUI

struct CollabTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @StateObject private var downloadCoordinator = SharedTapeDownloadCoordinator()
    @StateObject private var syncCoordinator = CollabSyncCoordinator()
    @StateObject private var importCoordinator = MediaImportCoordinator()
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @EnvironmentObject private var syncChecker: TapeSyncChecker
    @EnvironmentObject private var pendingInviteStore: PendingInviteStore
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @Environment(\.scenePhase) private var scenePhase

    @State private var tapeToPreview: Tape?
    @State private var playbackStartClip: Int = 0
    @State private var tapeToShare: Tape?
    @State private var tapeToSettings: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""
    @State private var inviteToDismiss: PendingInvite?
    @State private var selectedSegment: CollabSegment = .createdByMe
    @State private var isScrolled = false
    @State private var sortedOwnerIDs: [UUID] = []
    @State private var sortedReceivedIDs: [UUID] = []
    @State private var showingPaywall = false

    enum CollabSegment: String, CaseIterable, Identifiable {
        case createdByMe = "Created by me"
        case contributingTo = "Contributing to"
        var id: String { rawValue }
    }

    private var ownerCollabTapes: [Tape] {
        let tapes = tapesStore.tapes.filter { $0.isCollabTape }
        if sortedOwnerIDs.isEmpty { return tapes }
        let lookup = Dictionary(uniqueKeysWithValues: tapes.map { ($0.id, $0) })
        var ordered = sortedOwnerIDs.compactMap { lookup[$0] }
        let newTapes = tapes.filter { !sortedOwnerIDs.contains($0.id) }
        ordered.insert(contentsOf: newTapes, at: 0)
        return ordered
    }

    private var receivedCollabTapes: [Tape] {
        let tapes = tapesStore.tapes
            .filter { !$0.isCollabTape && $0.isShared && $0.shareInfo?.mode == "collaborative" }
        if sortedReceivedIDs.isEmpty { return tapes }
        let lookup = Dictionary(uniqueKeysWithValues: tapes.map { ($0.id, $0) })
        var ordered = sortedReceivedIDs.compactMap { lookup[$0] }
        let newTapes = tapes.filter { !sortedReceivedIDs.contains($0.id) }
        ordered.insert(contentsOf: newTapes, at: 0)
        return ordered
    }

    private func refreshSortOrder() {
        sortedOwnerIDs = tapesStore.tapes
            .filter { $0.isCollabTape }
            .sorted { a, b in
                let aEmpty = a.clips.isEmpty && !a.hasReceivedFirstContent
                let bEmpty = b.clips.isEmpty && !b.hasReceivedFirstContent
                if aEmpty != bEmpty { return aEmpty }

                let aHasDownloads = (syncChecker.pendingDownloads[a.id] ?? 0) > 0
                let bHasDownloads = (syncChecker.pendingDownloads[b.id] ?? 0) > 0
                if aHasDownloads != bHasDownloads { return aHasDownloads }

                return a.updatedAt > b.updatedAt
            }
            .map(\.id)

        sortedReceivedIDs = tapesStore.tapes
            .filter { !$0.isCollabTape && $0.isShared && $0.shareInfo?.mode == "collaborative" }
            .sorted { a, b in
                let aHasDownloads = (syncChecker.pendingDownloads[a.id] ?? 0) > 0
                let bHasDownloads = (syncChecker.pendingDownloads[b.id] ?? 0) > 0
                if aHasDownloads != bHasDownloads { return aHasDownloads }
                return a.updatedAt > b.updatedAt
            }
            .map(\.id)
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
                } else if !authManager.isEmailVerified {
                    unverifiedBanner
                } else {
                    collabTapeList
                }

                dialogOverlays
            }
            .modifier(SegmentedBarModifier(selection: $selectedSegment, isScrolled: isScrolled, isJiggling: tapesStore.jigglingTapeID != nil, showPicker: !receivedCollabTapes.isEmpty))
            .modifier(ScrollEdgeSoftModifier())
            .navigationTitle("Collab")
            .navigationBarTitleDisplayMode(receivedCollabTapes.isEmpty ? .large : .inline)
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
            .onAppear {
                if let shareId = navigationCoordinator.pendingCollabShareId {
                    navigationCoordinator.pendingCollabShareId = nil
                    selectedSegment = .contributingTo
                    handleIncomingCollabShare(shareId: shareId)
                }
                refreshSortOrder()
            }
            .onChange(of: navigationCoordinator.pendingCollabShareId) { _, shareId in
                if let shareId {
                    navigationCoordinator.pendingCollabShareId = nil
                    selectedSegment = .contributingTo
                    handleIncomingCollabShare(shareId: shareId)
                }
            }
            .onChange(of: receivedCollabTapes.isEmpty) { _, isEmpty in
                if isEmpty && selectedSegment == .contributingTo {
                    selectedSegment = .createdByMe
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
        .sheet(item: $tapeToShare) { shareTape in
            if let binding = tapesStore.bindingForTape(id: shareTape.id) {
                ShareModalView(tape: binding, pendingMergeTape: .constant(nil))
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
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
            TapePlayerView(tape: tape, startAtClip: playbackStartClip, onDismiss: {
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
                        if tapesStore.isFloatingClip {
                            tapesStore.returnFloatingClip()
                        }
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

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.m) {
                    Color.clear.frame(height: 0).id("collabListTop")

                    switch selectedSegment {
                    case .createdByMe:
                        ForEach(ownerCollabTapes) { tape in
                            if let binding = tapesStore.bindingForTape(id: tape.id) {
                                collabTapeCard(tape: tape, binding: binding, width: contentWidth, isOwner: true)
                            }
                        }
                    case .contributingTo:
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
            .scrollDisabled(tapesStore.isFloatingDragActive)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 4
            } action: { _, scrolled in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isScrolled = scrolled
                }
            }
            .onChange(of: downloadCoordinator.resultTape?.id) { _, newId in
                guard newId != nil else { return }
                withAnimation { proxy.scrollTo("collabListTop", anchor: .top) }
            }
            } // ScrollViewReader
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
            onShare: { handleShareIntent(for: tape) },
            onSettings: { tapeToSettings = tape },
            onPlay: { startIndex in
                tapesStore.clearUnseenContent(for: tape.id)
                var cleared = tape
                cleared.hasUnseenContent = false
                playbackStartClip = startIndex
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
            titleEditingConfig: titleConfig,
            onActivationBlocked: { showingPaywall = true }
        )
        .background(Tokens.Colors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(alignment: .bottomTrailing) {
            let total = syncCount(for: tape)
            let isActive = syncCoordinator.isSyncing
                || (uploadCoordinator.isUploading && uploadCoordinator.sourceTape?.id == tape.id)
                || downloadCoordinator.isDownloading
            if total > 0, tape.shareInfo != nil, !isActive, tapesStore.jigglingTapeID == nil {
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

    // MARK: - Share Intent

    /// Free-tier gate before opening the share sheet. Tapes that have
    /// already been activated (counted) bypass the gate; new ones present
    /// `PaywallView` if the user has hit the lifetime cap.
    private func handleShareIntent(for tape: Tape) {
        if !entitlementManager.isTapeAlreadyActivated(tape.id),
           !entitlementManager.canActivateNewTape() {
            showingPaywall = true
            return
        }
        tapeToShare = tape
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

    // MARK: - Handle Incoming Collab Share

    private func handleIncomingCollabShare(shareId: String) {
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

private struct ScrollEdgeSoftModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct SegmentedBarModifier: ViewModifier {
    @Binding var selection: CollabTapesView.CollabSegment
    var isScrolled: Bool
    var isJiggling: Bool
    var showPicker: Bool

    private var picker: some View {
        Picker("", selection: $selection) {
            ForEach(CollabTapesView.CollabSegment.allCases) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .disabled(isJiggling)
        .opacity(isJiggling ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.25), value: isJiggling)
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
    }

    func body(content: Content) -> some View {
        if showPicker {
            if #available(iOS 26.0, *) {
                content.safeAreaBar(edge: .top) { picker }
            } else {
                content.safeAreaInset(edge: .top, spacing: 0) {
                    picker.background(.bar)
                }
            }
        } else {
            content
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
