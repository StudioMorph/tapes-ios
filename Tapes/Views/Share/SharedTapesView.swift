import SwiftUI
import AuthenticationServices

struct SharedTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var downloadCoordinator = SharedTapeDownloadCoordinator()
    @StateObject private var importCoordinator = MediaImportCoordinator()
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @EnvironmentObject private var syncChecker: TapeSyncChecker

    @State private var tapeToPreview: Tape?
    @State private var tapeToShare: Tape?
    @State private var tapeToSettings: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""

    private var viewOnlyTapes: [Tape] {
        tapesStore.tapes
            .filter { $0.isShared && !$0.isCollabTape && ($0.shareInfo?.mode ?? "view_only") == "view_only" }
            .sorted { a, b in
                let aHas = syncChecker.pendingDownloads[a.id] != nil
                let bHas = syncChecker.pendingDownloads[b.id] != nil
                if aHas != bHas { return aHas }
                return a.updatedAt > b.updatedAt
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)

                if !authManager.isSignedIn {
                    signInPrompt
                } else if viewOnlyTapes.isEmpty {
                    emptyState
                } else {
                    sharedTapeList
                }

                SharedDownloadProgressOverlay(coordinator: downloadCoordinator)
            }
            .navigationTitle("Shared")
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
            .onChange(of: navigationCoordinator.pendingSharedTapeId) { _, newId in
                if let shareId = newId {
                    navigationCoordinator.clearPendingTape()
                    handleIncomingShare(shareId: shareId)
                }
            }
            .onAppear {
                if let shareId = navigationCoordinator.pendingSharedTapeId {
                    navigationCoordinator.clearPendingTape()
                    handleIncomingShare(shareId: shareId)
                }
            }
            .onChange(of: downloadCoordinator.resultTape?.id) { _, newId in
                guard newId != nil,
                      let tape = downloadCoordinator.resultTape,
                      tape.shareInfo?.mode == "collaborative" else { return }
                navigationCoordinator.selectedTab = .collab
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

    // MARK: - Shared Tape List

    private var sharedTapeList: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - (Tokens.Spacing.m * 2)

            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.m) {
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

            Text("Sign in to see shared tapes")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("Tapes shared with you will appear here after you sign in with your Apple ID.")
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
}
