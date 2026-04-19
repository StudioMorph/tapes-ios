import SwiftUI
import AuthenticationServices

struct CollabTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @StateObject private var downloadCoordinator = SharedTapeDownloadCoordinator()
    @StateObject private var importCoordinator = MediaImportCoordinator()
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @EnvironmentObject private var syncChecker: TapeSyncChecker

    @State private var tapeToPreview: Tape?
    @State private var tapeToShare: Tape?
    @State private var tapeToSettings: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""

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

                SharedDownloadProgressOverlay(coordinator: downloadCoordinator)
                ImportProgressOverlay(coordinator: importCoordinator)

                if isCollabUpload {
                    if uploadCoordinator.showProgressDialog {
                        ShareUploadProgressDialog(coordinator: uploadCoordinator)
                    }
                    if uploadCoordinator.showCompletionDialog {
                        ShareUploadCompletionDialog(coordinator: uploadCoordinator)
                    }
                    if uploadCoordinator.uploadError != nil {
                        ShareUploadErrorAlert(coordinator: uploadCoordinator)
                    }
                }
            }
            .navigationTitle("Collab")
            .navigationBarTitleDisplayMode(.large)
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

                    if !receivedCollabTapes.isEmpty {
                        Text("Collaborating")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Tokens.Spacing.s)

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
            onPlay: { tapeToPreview = tape },
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

        if hasUploads {
            let uploadAction: (Tape) -> Void = { tape in
                if tape.isCollabTape {
                    self.uploadCoordinator.ensureTapeUploaded(
                        tape: tape,
                        intendedForCollaboration: true,
                        api: api
                    ) { _ in
                        if hasDownloads, let shareId = tape.shareInfo?.shareId {
                            self.downloadCoordinator.startDownload(
                                shareId: shareId,
                                api: api,
                                tapeStore: self.tapesStore
                            )
                        }
                    }
                } else {
                    self.uploadCoordinator.contributeClips(tape: tape, api: api) { syncedIds in
                        for clipId in syncedIds {
                            self.tapesStore.markClipSynced(clipId, inTape: tape.id)
                        }
                        if hasDownloads, let shareId = tape.shareInfo?.shareId {
                            self.downloadCoordinator.startDownload(
                                shareId: shareId,
                                api: api,
                                tapeStore: self.tapesStore
                            )
                        }
                    }
                }
            }
            uploadAction(tape)
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
}
