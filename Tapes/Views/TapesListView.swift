import SwiftUI
import UIKit

struct TapesListView: View {
    @EnvironmentObject var tapesStore: TapesStore
    @StateObject private var exportCoordinator = ExportCoordinator()
    @State private var showingPlayer = false
    @State private var showingPlayOptions = false
    @State private var showingQAChecklist = false
    @State private var tapeToPreview: Tape?
    @State private var keyboardHeight: CGFloat = 0
    @State private var activeTapeID: UUID?
    @State private var scrollToTape: ((UUID) -> Void)?
    
    var body: some View {
        NavigationView {
            VStack {
                headerView
                tapesList
                Spacer()
            }
            .navigationBarHidden(true)
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
            guard let activeTapeID else { return }
            DispatchQueue.main.async {
                scrollToTape?(activeTapeID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            activeTapeID = nil
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
                LazyVStack(spacing: Tokens.Spacing.m) {  // 16pt vertical spacing between cards
                    ForEach($tapesStore.tapes) { $tape in
                        let tapeID = $tape.wrappedValue.id
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
                                    onSettings: { tapesStore.selectTape($tape.wrappedValue) },
                                    onPlay: {
                                        tapeToPreview = $tape.wrappedValue
                                        showingPlayOptions = true
                                    },
                                    onAirPlay: { },
                                    onThumbnailDelete: { clip in
                                        tapesStore.deleteClip(from: $tape.wrappedValue.id, clip: clip)
                                    },
                                    onClipInserted: { clip, index in
                                        tapesStore.insertClip(clip, in: $tape.wrappedValue.id, atCenterOfCarouselIndex: index)
                                    },
                                    onClipInsertedAtPlaceholder: { clip, placeholder in
                                        tapesStore.insertClipAtPlaceholder(clip, in: $tape.wrappedValue.id, placeholder: placeholder)
                                    },
                                onMediaInserted: { pickedMedia, strategy in
                                    tapesStore.insertMedia(pickedMedia, at: strategy, in: $tape.wrappedValue.id)
                                },
                                onTitleFocusRequest: {
                                    activeTapeID = tapeID
                                    DispatchQueue.main.async {
                                        scrollToTape?(tapeID)
                                    }
                                }
                            )
                        }
                        .padding(.horizontal, Tokens.Spacing.m)  // 16pt outer padding
                        .id(tapeID)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: keyboardHeight)
            }
            .onAppear {
                scrollToTape = { id in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .top)
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
        return ZStack {
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
