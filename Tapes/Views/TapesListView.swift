import SwiftUI

struct TapesListView: View {
    @EnvironmentObject var tapesStore: TapesStore
    @StateObject private var exportCoordinator = ExportCoordinator()
    @State private var showingPlayer = false
    @State private var showingPlayOptions = false
    @State private var showingQAChecklist = false
    @State private var tapeToPreview: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""
    @State private var showingDeleteSuccessToast = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background layer - ensures consistent background throughout
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)
                
                if !tapesStore.isLoaded {
                    Color.clear
                } else if tapesStore.tapes.isEmpty {
                    EmptyStateView()
                } else {
                    VStack(spacing: 0) {
                        HeaderView(onQAChecklistTapped: {
                            showingQAChecklist = true
                        })
                        
                        TapesList(
                            tapes: $tapesStore.tapes,
                            editingTapeID: editingTapeID,
                            draftTitle: $draftTitle,
                            onSettings: handleSettings,
                            onPlay: handlePlay,
                            onThumbnailDelete: handleThumbnailDelete,
                            onClipInserted: handleClipInserted,
                            onClipInsertedAtPlaceholder: handleClipInsertedAtPlaceholder,
                            onMediaInserted: handleMediaInserted,
                            onTitleFocusRequest: handleTitleFocusRequest,
                            onTitleCommit: commitTitleEditing
                        )
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $tapesStore.showingSettingsSheet) {
            settingsSheet
        }
        .confirmationDialog("Play Options", isPresented: $showingPlayOptions) {
            Button("Preview Tape") {
                if tapeToPreview == nil {
                    tapeToPreview = tapesStore.tapes.first(where: { !$0.clips.isEmpty })
                }
                showingPlayer = tapeToPreview != nil
            }
            Button("Merge & Save") {
                let tape = tapeToPreview ?? tapesStore.tapes.first(where: { !$0.clips.isEmpty })
                if let tape {
                    exportCoordinator.exportTape(tape) { newIdentifier in
                        tapesStore.updateTapeAlbumIdentifier(newIdentifier, for: tape.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            playerView
        }
        .overlay(exportOverlay)
        .sheet(isPresented: $showingQAChecklist) {
            QAChecklistView()
        }
    }

    // MARK: - Action Handlers
    
    private func handleSettings(_ tape: Tape) {
        tapesStore.selectTape(tape)
    }
    
    private func handlePlay(_ tape: Tape) {
        tapeToPreview = tape
        showingPlayOptions = true
    }
    
    private func handleThumbnailDelete(_ tape: Tape, _ clip: Clip) {
        tapesStore.deleteClip(from: tape.id, clip: clip)
    }
    
    private func handleClipInserted(_ tape: Tape, _ clip: Clip, _ index: Int) {
        tapesStore.insertClip(clip, in: tape.id, atCenterOfCarouselIndex: index)
    }
    
    private func handleClipInsertedAtPlaceholder(_ tape: Tape, _ clip: Clip, _ placeholder: CarouselItem) {
        tapesStore.insertClipAtPlaceholder(clip, in: tape.id, placeholder: placeholder)
    }
    
    private func handleMediaInserted(_ tape: Tape, _ media: [PickedMedia], _ strategy: InsertionStrategy) {
        tapesStore.insertMedia(media, at: strategy, in: tape.id)
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

    @ViewBuilder
    private var playerView: some View {
        if let tape = tapeToPreview {
            TapePlayerView(tape: tape, onDismiss: {
                showingPlayer = false
                tapeToPreview = nil
            })
        }
    }

    private var exportOverlay: some View {
        ZStack {
            if exportCoordinator.isExporting {
                ExportProgressOverlay(coordinator: exportCoordinator)
            }
            if exportCoordinator.showCompletionToast {
                CompletionToast(coordinator: exportCoordinator)
            }
            if exportCoordinator.exportError != nil {
                ExportErrorAlert(coordinator: exportCoordinator)
            }
            if showingDeleteSuccessToast {
                DeleteSuccessToast(isVisible: $showingDeleteSuccessToast)
            }
            AlbumAssociationAlert()
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
        .environmentObject(TapesStore())  // lightweight preview store
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapesListView()
        .environmentObject(TapesStore())  // lightweight preview store
        .preferredColorScheme(.light)
}
