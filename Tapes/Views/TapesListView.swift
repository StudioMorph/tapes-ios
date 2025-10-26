import SwiftUI

struct TapesListView: View {
    @EnvironmentObject var tapesStore: TapesStore
    @StateObject private var exportCoordinator = ExportCoordinator()
    @State private var showingPlayer = false
    @State private var showingPlayOptions = false
    @State private var showingQAChecklist = false
    @State private var tapeToPreview: Tape?
    @State private var tapeFrames: TapeFrameMap = [:]
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollToTape: ((UUID, UnitPoint) -> Void)?
    @State private var editingTapeID: UUID?
    @State private var editingSessionID: UUID?
    @State private var draftTitle: String = ""
    @State private var viewportFrame: CGRect = .zero
    @State private var additionalScrollInset: CGFloat = 0
    private let fallbackKeyboardHeight: CGFloat = 320

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                VStack {
                    headerView
                    tapesList
                    Spacer()
                }
                .navigationBarHidden(true)
            }
        }
        .background(Tokens.Colors.bg)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = keyboardHeight(from: notification)
            if let editingTapeID {
                ensureTapeVisible(tapeID: editingTapeID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            setAdditionalScrollInset(0, animate: true)
        }
        .onChange(of: keyboardHeight) { _ in
            if let editingTapeID {
                ensureTapeVisible(tapeID: editingTapeID)
            }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.m) {
                    ForEach($tapesStore.tapes) { $tape in
                        let tapeID = $tape.wrappedValue.id
                        let onSettings = { tapesStore.selectTape($tape.wrappedValue) }
                        let onPlay: () -> Void = {
                            tapeToPreview = $tape.wrappedValue
                            showingPlayOptions = true
                        }
                        let onAirPlay: () -> Void = { }
                        let onThumbnailDelete: (Clip) -> Void = { clip in
                            tapesStore.deleteClip(from: $tape.wrappedValue.id, clip: clip)
                        }
                        let onClipInserted: (Clip, Int) -> Void = { clip, index in
                            tapesStore.insertClip(clip, in: $tape.wrappedValue.id, atCenterOfCarouselIndex: index)
                        }
                        let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void = { clip, placeholder in
                            tapesStore.insertClipAtPlaceholder(clip, in: $tape.wrappedValue.id, placeholder: placeholder)
                        }
                        let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void = { pickedMedia, strategy in
                            tapesStore.insertMedia(pickedMedia, at: strategy, in: $tape.wrappedValue.id)
                        }
                        let isEditingTitle = editingTapeID == tapeID
                        let titleEditingConfig: TapeCardView.TitleEditingConfig? = {
                            guard isEditingTitle, let focusID = editingSessionID else { return nil }
                            return TapeCardView.TitleEditingConfig(
                                text: Binding(
                                    get: { draftTitle },
                                    set: { draftTitle = $0 }
                                ),
                                focusSessionID: focusID,
                                onCommit: commitTitleEditing,
                                onCancel: cancelTitleEditing
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
                                onSettings: onSettings,
                                onPlay: onPlay,
                                onAirPlay: onAirPlay,
                                onThumbnailDelete: onThumbnailDelete,
                                onClipInserted: onClipInserted,
                                onClipInsertedAtPlaceholder: onClipInsertedAtPlaceholder,
                                onMediaInserted: onMediaInserted,
                                onTitleFocusRequest: {
                                    startTitleEditing(tapeID: tapeID, currentTitle: $tape.wrappedValue.title)
                                },
                                isDimmed: editingTapeID != nil && editingTapeID != tapeID,
                                titleEditingConfig: titleEditingConfig
                            )
                        }
                        .padding(.horizontal, Tokens.Spacing.m)
                        .id(tapeID)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TapeFramePreferenceKey.self, value: [tapeID: geo.frame(in: .global)])
                            }
                        )
                    }
                }
                .padding(.bottom, max(0, keyboardHeight) + additionalScrollInset + Tokens.Spacing.l)
                .onPreferenceChange(TapeFramePreferenceKey.self) { value in
                    tapeFrames.merge(value) { _, new in new }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ViewportFramePreferenceKey.self, value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(ViewportFramePreferenceKey.self) { frame in
                viewportFrame = frame
            }
            .onAppear {
                scrollToTape = { id, anchor in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: anchor)
                    }
                }
            }
            .onDisappear {
                scrollToTape = nil
            }
        }
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

private func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return 0 }
        return frameValue.cgRectValue.height
    }

    private func startTitleEditing(tapeID: UUID, currentTitle: String) {
        if editingTapeID != nil {
            cancelTitleEditing()
        }
        editingTapeID = tapeID
        draftTitle = currentTitle
        editingSessionID = UUID()
        ensureTapeVisible(
            tapeID: tapeID,
            keyboardHeightOverride: keyboardHeight > 0 ? keyboardHeight : fallbackKeyboardHeight,
            animateInset: false
        )
        DispatchQueue.main.async {
            ensureTapeVisible(tapeID: tapeID, keyboardHeightOverride: self.keyboardHeight > 0 ? self.keyboardHeight : self.fallbackKeyboardHeight)
        }
    }

    private func commitTitleEditing() {
        guard let editingTapeID else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        tapesStore.renameTapeTitle(editingTapeID, to: trimmed)
        resetTitleEditingState()
    }

    private func cancelTitleEditing() {
        resetTitleEditingState()
    }

    private func resetTitleEditingState() {
        editingTapeID = nil
        editingSessionID = nil
        draftTitle = ""
        setAdditionalScrollInset(0, animate: true)
    }

    private func ensureTapeVisible(
        tapeID: UUID,
        keyboardHeightOverride: CGFloat? = nil,
        animateInset: Bool = true
    ) {
        guard editingTapeID == tapeID else { return }
        let effectiveHeight = max(keyboardHeightOverride ?? keyboardHeight, 0)
        if effectiveHeight > 0 {
            updateScrollInset(for: tapeID, keyboardHeight: effectiveHeight, animate: animateInset)
            scrollCardIfNeeded(tapeID: tapeID, keyboardHeight: effectiveHeight)
            DispatchQueue.main.async {
                guard self.editingTapeID == tapeID else { return }
                self.updateScrollInset(for: tapeID, keyboardHeight: effectiveHeight, animate: animateInset)
                self.scrollCardIfNeeded(tapeID: tapeID, keyboardHeight: effectiveHeight)
                DispatchQueue.main.async {
                    guard self.editingTapeID == tapeID else { return }
                    self.scrollCardIfNeeded(tapeID: tapeID, keyboardHeight: effectiveHeight)
                }
            }
        } else {
            scrollCardIfNeeded(tapeID: tapeID, keyboardHeight: 0)
        }
    }

    private func updateScrollInset(for tapeID: UUID, keyboardHeight: CGFloat, animate: Bool) {
        guard keyboardHeight > 0 else {
            setAdditionalScrollInset(0, animate: animate)
            return
        }
        guard let frame = tapeFrames[tapeID], viewportFrame != .zero else {
            let fallback = min(max(keyboardHeight * 0.45, 0), 180)
            setAdditionalScrollInset(max(additionalScrollInset, fallback), animate: animate)
            return
        }
        let padding: CGFloat = 16
        let keyboardTop = viewportFrame.maxY - keyboardHeight
        let overlap = frame.maxY + padding - keyboardTop
        let newInset = max(0, overlap)
        let clamped = max(newInset, min(max(keyboardHeight * 0.35, 0), 140))
        setAdditionalScrollInset(clamped, animate: animate)
    }

    private func setAdditionalScrollInset(_ inset: CGFloat, animate: Bool) {
        let clamped = max(0, inset)
        guard abs(clamped - additionalScrollInset) > 0.1 else { return }
        if animate {
            withAnimation(.easeInOut(duration: 0.2)) {
                additionalScrollInset = clamped
            }
        } else {
            additionalScrollInset = clamped
        }
    }

    private func scrollCardIfNeeded(tapeID: UUID, keyboardHeight: CGFloat) {
        guard let scrollToTape else { return }
        guard let frame = tapeFrames[tapeID], viewportFrame != .zero else {
            scrollToTape(tapeID, .bottom)
            return
        }
        let padding: CGFloat = 16
        let visibleTop = viewportFrame.minY + padding
        let keyboardTop = viewportFrame.maxY - keyboardHeight
        if keyboardHeight > 0, frame.maxY > keyboardTop - padding {
            scrollToTape(tapeID, .bottom)
        } else if frame.minY < visibleTop {
            scrollToTape(tapeID, .top)
        }
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
