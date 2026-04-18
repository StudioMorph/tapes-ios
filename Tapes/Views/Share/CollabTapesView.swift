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

    private var collabTapes: [Tape] {
        tapesStore.sharedTapes.filter { $0.shareInfo?.mode == "collaborative" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)

                if !authManager.isSignedIn {
                    signInPrompt
                } else if collabTapes.isEmpty {
                    emptyState
                } else {
                    collabTapeList
                }

                SharedDownloadProgressOverlay(coordinator: downloadCoordinator)

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
                    ForEach(collabTapes) { tape in
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
                                onShare: { tapeToShare = tape },
                                onSettings: { tapeToSettings = tape },
                                onPlay: { tapeToPreview = tape },
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
                                if let count = syncChecker.pendingDownloads[tapeID], count > 0 {
                                    SyncBadge(count: count, direction: .download) {
                                        handleDownload(tape: tape)
                                    }
                                }
                            }
                            .compositingGroup()
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.s)
            }
        }
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

            Text("Collaborative tapes will appear here after you sign in with your Apple ID.")
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "person.2.wave.2")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text("No collaborative tapes yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("When you collaborate on a tape, it will appear here.")
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
    CollabTapesView()
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
        .environmentObject(NavigationCoordinator())
        .environmentObject(ShareUploadCoordinator())
        .environmentObject(TapeSyncChecker())
}
