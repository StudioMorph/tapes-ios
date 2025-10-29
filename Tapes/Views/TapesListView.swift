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
                
                if tapesStore.tapes.isEmpty {
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
                            onAirPlay: handleAirPlay,
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
        .actionSheet(isPresented: $showingPlayOptions) {
            playOptionsSheet
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
        print("🔧 onSettings called for tape: \(tape.title)")
        tapesStore.selectTape(tape)
    }
    
    private func handlePlay(_ tape: Tape) {
        print("▶️ onPlay called for tape: \(tape.title)")
        tapeToPreview = tape
        showingPlayOptions = true
    }
    
    private func handleAirPlay(_ tape: Tape) {
        // AirPlay functionality - currently empty
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

    private var settingsSheet: some View {
        if let selectedTape = tapesStore.selectedTape {
            return AnyView(TapeSettingsView(
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
            ))
        } else {
            return AnyView(EmptyView())
        }
    }

    private var playOptionsSheet: ActionSheet {
        ActionSheet(
            title: Text("Play Options"),
            buttons: [
                .default(Text("Preview Tape")) {
                    if tapeToPreview == nil {
                        tapeToPreview = tapesStore.tapes.first(where: { !$0.clips.isEmpty })
                    }
                    showingPlayer = tapeToPreview != nil
                },
                .default(Text("Merge & Save")) {
                    if let tape = tapesStore.tapes.first {
                        exportCoordinator.exportTape(tape) { newIdentifier in
                            tapesStore.updateTapeAlbumIdentifier(newIdentifier, for: tape.id)
                        }
                    }
                },
                .cancel()
            ]
        )
    }

    private var playerView: some View {
        if let tape = tapeToPreview {
            return AnyView(TapePlayerView(tape: tape, onDismiss: {
                showingPlayer = false
                tapeToPreview = nil
            }))
        } else {
            return AnyView(EmptyView())
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

private struct NewTapeRevealContainer<Content: View>: View {
    let tapeID: UUID
    let isNewlyInserted: Bool
    let isPendingReveal: Bool
    let onAnimationCompleted: () -> Void
    let content: () -> Content

    @State private var hasAnimated = false
    @State private var isVisible = false

    private let listSlideDuration: Double = 0.42
    private let animationDuration: Double = 0.32
    private let revealAnimation = Animation.interactiveSpring(response: 0.36, dampingFraction: 0.85, blendDuration: 0.12)

    init(
        tapeID: UUID,
        isNewlyInserted: Bool,
        isPendingReveal: Bool,
        onAnimationCompleted: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tapeID = tapeID
        self.isNewlyInserted = isNewlyInserted
        self.isPendingReveal = isPendingReveal
        self.onAnimationCompleted = onAnimationCompleted
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(targetScale, anchor: .center)
            .opacity(targetOpacity)
            .allowsHitTesting(true)
            .onAppear {
                if isPendingReveal {
                    isVisible = false
                    hasAnimated = false
                    return
                }
                guard isNewlyInserted else {
                    isVisible = true
                    return
                }
                guard !hasAnimated else { return }
                hasAnimated = true
                isVisible = false
                reveal(after: listSlideDuration)
            }
            .onChange(of: isNewlyInserted) { newValue in
                if newValue {
                    guard !hasAnimated else { return }
                    hasAnimated = true
                    isVisible = false
                    reveal(after: 0)
                } else {
                    isVisible = true
                }
            }
            .onChange(of: isPendingReveal) { pending in
                if pending {
                    isVisible = false
                    hasAnimated = false
                }
            }
    }

    private var targetScale: CGFloat {
        if isPendingReveal { return 0.85 }
        guard isNewlyInserted else { return 1.0 }
        return isVisible ? 1.0 : 0.85
    }

    private var targetOpacity: Double {
        if isPendingReveal { return 0.0 }
        guard isNewlyInserted else { return 1.0 }
        return isVisible ? 1.0 : 0.0
    }

    private func reveal(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(revealAnimation) {
                isVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + animationDuration) {
            onAnimationCompleted()
        }
    }
}

private struct AlbumAssociationAlert: View {
    @EnvironmentObject var tapesStore: TapesStore

    var body: some View {
        EmptyView()
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
                
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation {
                        showing = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isVisible = false
                    }
                }
            }
            .onTapGesture {
                withAnimation {
                    showing = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
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
