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

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                VStack {
                    headerView
                    tapesList
                }
                .navigationBarHidden(true)
            }
        }
        .background(Tokens.Colors.bg)
        .background(Tokens.Colors.bg.ignoresSafeArea())
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

    private var headerView: some View {
        HStack {
            Text("TAPES")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Tokens.Colors.red)

            Spacer()

            Button(action: { showingQAChecklist = true }) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.red)
            }
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.top, Tokens.Spacing.s)
    }

    private var tapesList: some View {
        List {
            ForEach($tapesStore.tapes) { $tape in
                let tapeID = $tape.wrappedValue.id
                let currentTape = $tape.wrappedValue
                let onSettings = { 
                    print("🔧 onSettings called for tape: \(currentTape.title)")
                    tapesStore.selectTape(currentTape) 
                }
                let onPlay: () -> Void = {
                    print("▶️ onPlay called for tape: \(currentTape.title)")
                    tapeToPreview = currentTape
                    showingPlayOptions = true
                }
                let onAirPlay: () -> Void = { }
                let onThumbnailDelete: (Clip) -> Void = { clip in
                    tapesStore.deleteClip(from: currentTape.id, clip: clip)
                }
                let onClipInserted: (Clip, Int) -> Void = { clip, index in
                    tapesStore.insertClip(clip, in: currentTape.id, atCenterOfCarouselIndex: index)
                }
                let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void = { clip, placeholder in
                    tapesStore.insertClipAtPlaceholder(clip, in: currentTape.id, placeholder: placeholder)
                }
                let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void = { pickedMedia, strategy in
                    tapesStore.insertMedia(pickedMedia, at: strategy, in: currentTape.id)
                }

                let titleEditingConfig: TapeCardView.TitleEditingConfig? = {
                    guard editingTapeID == tapeID else { return nil }
                    return TapeCardView.TitleEditingConfig(
                        text: Binding(
                            get: { draftTitle },
                            set: { draftTitle = $0 }
                        ),
                        tapeID: tapeID,
                        onCommit: commitTitleEditing
                    )
                }()

                NewTapeRevealContainer(
                    tapeID: tapeID,
                    isNewlyInserted: tapesStore.latestInsertedTapeID == tapeID,
                    isPendingReveal: tapesStore.pendingTapeRevealID == tapeID,
                    onAnimationCompleted: {
                        tapesStore.clearLatestInsertedTapeID(tapeID)
                    }
                ) {
                    TapeCardView(
                        tape: $tape,
                        tapeID: tapeID,
                        onSettings: onSettings,
                        onPlay: onPlay,
                        onAirPlay: onAirPlay,
                        onThumbnailDelete: onThumbnailDelete,
                        onClipInserted: onClipInserted,
                        onClipInsertedAtPlaceholder: onClipInsertedAtPlaceholder,
                        onMediaInserted: onMediaInserted,
                        onTitleFocusRequest: {
                            startTitleEditing(tapeID: tapeID, currentTitle: currentTape.title)
                        },
                        titleEditingConfig: titleEditingConfig
                    )
                }
                .listRowInsets(EdgeInsets(top: 8, leading: Tokens.Spacing.m, bottom: 8, trailing: Tokens.Spacing.m))
                .listRowSeparator(.hidden)
                .id(tapeID)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    private var settingsSheet: some View {
        if let selectedTape = tapesStore.selectedTape {
            return AnyView(TapeSettingsSheet(
                tape: Binding(
                    get: { selectedTape },
                    set: { tapesStore.updateTape($0) }
                ),
                onDismiss: {
                    tapesStore.showingSettingsSheet = false
                    tapesStore.clearSelectedTape()
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
            AlbumAssociationAlert()
        }
    }

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
