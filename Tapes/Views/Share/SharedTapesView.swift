import SwiftUI
import AuthenticationServices

struct SharedTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @StateObject private var downloadCoordinator = SharedTapeDownloadCoordinator()
    @StateObject private var importCoordinator = MediaImportCoordinator()
    @StateObject private var cameraCoordinator = CameraCoordinator()

    @State private var tapeToPreview: Tape?
    @State private var tapeToShare: Tape?
    @State private var selectedSegment: SharedSegment = .viewOnly

    enum SharedSegment: String, CaseIterable {
        case viewOnly = "View Only"
        case collaborating = "Collaborating"
    }

    private var filteredTapes: [Tape] {
        tapesStore.sharedTapes.filter { tape in
            guard let mode = tape.shareInfo?.mode else { return selectedSegment == .viewOnly }
            switch selectedSegment {
            case .viewOnly:
                return mode == "view_only"
            case .collaborating:
                return mode == "collaborative"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)

                if !authManager.isSignedIn {
                    signInPrompt
                } else {
                    VStack(spacing: 0) {
                        Picker("", selection: $selectedSegment) {
                            ForEach(SharedSegment.allCases, id: \.self) { segment in
                                Text(segment.rawValue).tag(segment)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Tokens.Spacing.m)
                        .padding(.top, Tokens.Spacing.s)

                        if filteredTapes.isEmpty {
                            emptyState
                        } else {
                            sharedTapeList
                        }
                    }
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
            .onChange(of: downloadCoordinator.resultTape) { _, tape in
                guard let mode = tape?.shareInfo?.mode else { return }
                withAnimation {
                    selectedSegment = mode == "collaborative" ? .collaborating : .viewOnly
                }
            }
            .onAppear {
                if let shareId = navigationCoordinator.pendingSharedTapeId {
                    navigationCoordinator.clearPendingTape()
                    handleIncomingShare(shareId: shareId)
                }
            }
        }
        .environmentObject(importCoordinator)
        .sheet(item: $tapeToShare) { tape in
            ShareModalView(tape: tape)
        }
        .sheet(isPresented: $tapesStore.showingSettingsSheet) {
            if let selectedTape = tapesStore.selectedTape {
                TapeSettingsView(
                    tape: Binding(
                        get: { selectedTape },
                        set: { tapesStore.updateTape($0) }
                    ),
                    onDismiss: {
                        tapesStore.showingSettingsSheet = false
                        tapesStore.clearSelectedTape()
                    },
                    onTapeDeleted: {},
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
                    ForEach(filteredTapes) { tape in
                        if let binding = tapesStore.bindingForTape(id: tape.id) {
                            let isCollaborative = tape.shareInfo?.mode == "collaborative"
                            TapeCardView(
                                tape: binding,
                                tapeID: tape.id,
                                tapeWidth: contentWidth,
                                isLandscape: false,
                                isShareDisabled: !isCollaborative,
                                onShare: { tapeToShare = tape },
                                onSettings: { tapesStore.selectTape(tape) },
                                onPlay: { tapeToPreview = tape },
                                onThumbnailDelete: { _ in },
                                onCameraCapture: { completion in
                                    cameraCoordinator.presentCamera(completion: completion)
                                },
                                onTitleFocusRequest: {},
                                titleEditingConfig: nil
                            )
                            .background(Tokens.Colors.primaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
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
}

#Preview {
    SharedTapesView()
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
        .environmentObject(NavigationCoordinator())
        .environmentObject(ShareUploadCoordinator())
}
