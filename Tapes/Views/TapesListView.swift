import SwiftUI

struct TapesListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var tapesStore: TapesStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var exportCoordinator = ExportCoordinator()
    @EnvironmentObject private var shareUploadCoordinator: ShareUploadCoordinator
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @StateObject private var importCoordinator = MediaImportCoordinator()
    @State private var tapeToPreview: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""
    @State private var showingDeleteSuccessToast = false
    @State private var showInlineTitle = false
    @State private var tapeToShare: Tape?
    @State private var pendingMergeTape: Tape?
    private var isMyTapeUpload: Bool {
        guard let source = shareUploadCoordinator.sourceTape else { return false }
        return !source.isCollabTape && source.shareInfo?.mode != "collaborative"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)
                
                if !tapesStore.isLoaded {
                    Color.clear
                } else if tapesStore.myTapes.isEmpty {
                    EmptyStateView()
                } else {
                    TapesList(
                        tapes: $tapesStore.tapes,
                        editingTapeID: editingTapeID,
                        draftTitle: $draftTitle,
                        onShare: handleShare,
                        onSettings: handleSettings,
                        onPlay: handlePlay,
                        onThumbnailDelete: handleThumbnailDelete,
                        onCameraCapture: handleCameraCapture,
                        onTitleFocusRequest: handleTitleFocusRequest,
                        onTitleCommit: commitTitleEditing,
                        onSyncUpload: { tape in triggerSyncUpload(tape) },
                        showInlineTitle: $showInlineTitle
                    )
                }

            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(colorScheme == .dark ? "Tapes_logo-Dark mode" : "Tapes_logo-Light mode")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                        .opacity(showInlineTitle ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: showInlineTitle)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                exportCoordinator.handleScenePhaseChange(newPhase)
                shareUploadCoordinator.handleScenePhaseChange(newPhase)
            }
            .onChange(of: shareUploadCoordinator.lastUploadedClipCount) { _, count in
                guard let count,
                      let source = shareUploadCoordinator.sourceTape,
                      !source.isCollabTape else { return }
                tapesStore.setLastUploadedClipCount(count, for: source.id)
            }
            .onChange(of: shareUploadCoordinator.lastSyncedClipIds) { _, ids in
                guard !ids.isEmpty,
                      let source = shareUploadCoordinator.sourceTape,
                      !source.isCollabTape else { return }
                for clipId in ids {
                    tapesStore.markClipSynced(clipId, inTape: source.id)
                }
            }
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
                    if exportCoordinator.isExporting && !exportCoordinator.showProgressDialog {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                exportCoordinator.showProgressDialogAgain()
                            } label: {
                                ZStack {
                                    CircularProgressRing(
                                        progress: exportCoordinator.progress,
                                        lineWidth: 2.5,
                                        size: 22,
                                        ringColor: .green
                                    )
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                    }
                    if isMyTapeUpload && shareUploadCoordinator.isUploading && !shareUploadCoordinator.showProgressDialog {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                shareUploadCoordinator.showProgressDialogAgain()
                            } label: {
                                ZStack {
                                    CircularProgressRing(
                                        progress: shareUploadCoordinator.progress,
                                        lineWidth: 2.5,
                                        size: 22,
                                        ringColor: .blue
                                    )
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                    }
                }
            }
        }
        .environmentObject(importCoordinator)
        .sheet(isPresented: $tapesStore.showingSettingsSheet) {
            settingsSheet
        }
        .sheet(item: $tapeToShare, onDismiss: {
            if let tape = pendingMergeTape {
                pendingMergeTape = nil
                handleMergeAndSave(tape)
            }
        }) { shareTape in
            if let binding = tapesStore.bindingForTape(id: shareTape.id) {
                ShareModalView(tape: binding, pendingMergeTape: $pendingMergeTape)
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
        .overlay(exportOverlay)
    }

    // MARK: - Action Handlers

    private func handleShare(_ tape: Tape) {
        tapeToShare = tape
    }

    private func triggerSyncUpload(_ tape: Tape) {
        guard let api = authManager.apiClient else { return }
        shareUploadCoordinator.ensureTapeUploaded(
            tape: tape,
            intendedForCollaboration: false,
            api: api
        )
    }

    private func handleSettings(_ tape: Tape) {
        tapesStore.selectTape(tape)
    }
    
    private func handlePlay(_ tape: Tape) {
        tapesStore.clearUnseenContent(for: tape.id)
        var cleared = tape
        cleared.hasUnseenContent = false
        tapeToPreview = cleared
    }

    private func handleCameraCapture(completion: @escaping ([PickedMedia]) -> Void) {
        cameraCoordinator.presentCamera(completion: completion)
    }

    private func handleMergeAndSave(_ tape: Tape) {
        exportCoordinator.exportTape(tape) { newIdentifier in
            tapesStore.updateTapeAlbumIdentifier(newIdentifier, for: tape.id)
        }
    }
    
    private func handleThumbnailDelete(_ tape: Tape, _ clip: Clip) {
        tapesStore.deleteClip(from: tape.id, clip: clip)
    }
    
    private func handleTitleFocusRequest(_ tapeID: UUID, _ currentTitle: String) {
        startTitleEditing(tapeID: tapeID, currentTitle: currentTitle)
    }

    @ViewBuilder
    private var settingsSheet: some View {
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
                onTapeDeleted: {
                    showingDeleteSuccessToast = true
                }
            )
        }
    }

    private var exportOverlay: some View {
        ZStack {
            if exportCoordinator.showProgressDialog {
                ExportProgressDialog(coordinator: exportCoordinator)
            }
            if exportCoordinator.showCompletionDialog {
                ExportCompletionDialog(coordinator: exportCoordinator)
            }
            if exportCoordinator.exportError != nil {
                ExportErrorAlert(coordinator: exportCoordinator)
            }
            if isMyTapeUpload {
                if shareUploadCoordinator.showProgressDialog {
                    ShareUploadProgressDialog(coordinator: shareUploadCoordinator)
                }
                if shareUploadCoordinator.showCompletionDialog {
                    ShareUploadCompletionDialog(coordinator: shareUploadCoordinator)
                }
                if shareUploadCoordinator.uploadError != nil {
                    ShareUploadErrorAlert(coordinator: shareUploadCoordinator)
                }
                if shareUploadCoordinator.showPostUploadDialog {
                    SharePostUploadDialog(coordinator: shareUploadCoordinator)
                }
            }
            if showingDeleteSuccessToast {
                DeleteSuccessToast(isVisible: $showingDeleteSuccessToast)
            }
            AlbumAssociationAlert()
            ImportProgressOverlay(coordinator: importCoordinator)
        }
    }

    // MARK: - Title Editing
    
    private func startTitleEditing(tapeID: UUID, currentTitle: String) {
        if editingTapeID != tapeID {
            cancelTitleEditing()
        }
        editingTapeID = tapeID
        draftTitle = currentTitle
    }

    private func commitTitleEditing() {
        guard let currentEditing = editingTapeID else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        tapesStore.renameTapeTitle(currentEditing, to: trimmed)
        editingTapeID = nil
        draftTitle = ""
    }

    private func cancelTitleEditing() {
        guard editingTapeID != nil else { return }
        editingTapeID = nil
        draftTitle = ""
    }
}

private struct AlbumAssociationAlert: View {
    @EnvironmentObject var tapesStore: TapesStore

    var body: some View {
        Color.clear
            .alert("Photos Album", isPresented: binding) {
                Button("OK") {
                    tapesStore.albumAssociationError = nil
                }
            } message: {
                if let message = tapesStore.albumAssociationError {
                    Text(message)
                }
            }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { tapesStore.albumAssociationError != nil },
            set: { newValue in
                if !newValue {
                    tapesStore.albumAssociationError = nil
                }
            }
        )
    }
}

// MARK: - Delete Success Toast

private struct DeleteSuccessToast: View {
    @Binding var isVisible: Bool
    @State private var showing = false

    private var displayDuration: TimeInterval { 3.0 }
    private var dismissAnimationDuration: TimeInterval { 0.4 }
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: Tokens.Spacing.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Tokens.Colors.primaryText)
                
                Text("Tape deleted")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Tokens.Colors.primaryText)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.vertical, Tokens.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                    .fill(Tokens.Colors.red)
            )
            .padding(.horizontal, Tokens.Spacing.l)
            .padding(.bottom, Tokens.Spacing.l)
            .opacity(showing ? 1.0 : 0.0)
            .scaleEffect(showing ? 1.0 : 0.8)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showing)
            .onAppear {
                showing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
                    withAnimation { showing = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + dismissAnimationDuration) {
                        isVisible = false
                    }
                }
            }
            .onTapGesture {
                withAnimation { showing = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + dismissAnimationDuration) {
                    isVisible = false
                }
            }
        }
    }
}

#Preview("Dark Mode") {
    TapesListView()
        .environmentObject(TapesStore())
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapesListView()
        .environmentObject(TapesStore())
        .preferredColorScheme(.light)
}
