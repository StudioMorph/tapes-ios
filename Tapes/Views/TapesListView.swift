import SwiftUI

struct TapesListView: View {
    @EnvironmentObject var tapesStore: TapesStore
    @StateObject private var exportCoordinator = ExportCoordinator()
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @State private var tapeToPreview: Tape?
    @State private var editingTapeID: UUID?
    @State private var draftTitle: String = ""
    @State private var showingDeleteSuccessToast = false
    @State private var dropTargets: [DropTargetInfo] = []
    @State private var hoveredTarget: DropTargetInfo? = nil
    @Binding var showOnboarding: Bool
    @AppStorage("tapes_hot_tips_remaining") private var hotTipsRemaining = 5
    @State private var showHotTips = false
    @State private var hotTipsJiggling = false
    @State private var showingAccountSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Colors.primaryBackground
                    .ignoresSafeArea(.all)
                
                if !tapesStore.isLoaded {
                    Color.clear
                } else if tapesStore.tapes.isEmpty {
                    EmptyStateView()
                } else {
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
                        onCameraCapture: handleCameraCapture,
                        onTitleFocusRequest: handleTitleFocusRequest,
                        onTitleCommit: commitTitleEditing
                    )
                }

                if let clip = tapesStore.floatingClip {
                    GeometryReader { containerGeo in
                        let origin = containerGeo.frame(in: .global).origin
                        floatingClipOverlay(clip: clip, containerOrigin: origin)
                    }
                }
            }
            .onPreferenceChange(DropTargetPreferenceKey.self) { targets in
                dropTargets = targets
            }
            .onChange(of: tapesStore.floatingPosition) { _, newPos in
                if tapesStore.isFloatingClip {
                    updateHoverTarget(at: newPos)
                }
            }
            .onChange(of: tapesStore.floatingDragDidEnd) { _, didEnd in
                guard didEnd, tapesStore.isFloatingClip else { return }
                tapesStore.isFloatingDragActive = false
                let location = tapesStore.floatingPosition
                let target = dropTargets.first {
                    $0.frame.contains(location) && $0.tapeID == tapesStore.jigglingTapeID
                }
                if let target {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        tapesStore.dropFloatingClip(onTape: target.tapeID, atIndex: target.insertionIndex, afterClipID: target.seamLeftClipID, beforeClipID: target.seamRightClipID)
                    }
                }
                hoveredTarget = nil
                tapesStore.floatingDragDidEnd = false
            }
            .navigationTitle("TAPES")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { Self.applyLargeTitleAppearance() }
            .onDisappear { Self.resetTitleAppearance() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if tapesStore.jigglingTapeID != nil {
                        Button("Done") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if tapesStore.isFloatingClip {
                                    tapesStore.returnFloatingClip()
                                }
                                tapesStore.jigglingTapeID = nil
                            }
                        }
                        .font(.body.weight(.semibold))
                    } else {
                        HStack(spacing: Tokens.Spacing.m) {
                            if exportCoordinator.isExporting && !exportCoordinator.showProgressDialog {
                                Button {
                                    exportCoordinator.showProgressDialogAgain()
                                } label: {
                                    ZStack {
                                        CircularProgressRing(
                                            progress: exportCoordinator.progress,
                                            lineWidth: 2.5,
                                            size: 28,
                                            ringColor: .green
                                        )
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Tokens.Colors.primaryText)
                                    }
                                    .frame(width: 36, height: 36)
                                    .background(Tokens.Colors.secondaryBackground, in: Circle())
                                }
                            }

                            Button {
                                showingAccountSettings = true
                            } label: {
                                Image(systemName: "person")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Tokens.Colors.secondaryBackground, in: Circle())
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAccountSettings) {
                AccountSettingsView(onHotTips: { showOnboarding = true })
            }
        }
        .sheet(isPresented: $tapesStore.showingSettingsSheet) {
            settingsSheet
        }
        .fullScreenCover(item: $tapeToPreview) { tape in
            TapePlayerView(tape: tape, onDismiss: {
                tapeToPreview = nil
            })
        }
        .fullScreenCover(isPresented: $cameraCoordinator.isPresented) {
            CameraView(coordinator: cameraCoordinator)
                .ignoresSafeArea(.all, edges: .all)
        }
        .overlay(exportOverlay)
        // MARK: - Floating Hot Tips button (deactivated — kept for future use)
        .overlay {
            if false, hotTipsJiggling {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { hotTipsJiggling = false }
                    }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if false, hotTipsRemaining > 0 {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "lightbulb.max")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 48, height: 48)
                        .background(Tokens.Colors.secondaryBackground, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .contentShape(Circle())
                        .onTapGesture {
                            if hotTipsJiggling {
                                withAnimation { hotTipsJiggling = false }
                            } else {
                                showOnboarding = true
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            withAnimation { hotTipsJiggling = true }
                        }
                        .rotationEffect(hotTipsJiggling ? .degrees(3) : .degrees(0))
                        .animation(
                            hotTipsJiggling
                                ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true)
                                : .default,
                            value: hotTipsJiggling
                        )

                    if hotTipsJiggling {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                hotTipsRemaining = 0
                                hotTipsJiggling = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(.red, in: Circle())
                        }
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.l)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            // Hot tips visit tracking deactivated — kept for future use
        }
    }

    // MARK: - Navigation Bar Appearance

    private static func applyLargeTitleAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 46, weight: .heavy)
        ]
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func resetTitleAppearance() {
        UINavigationBar.appearance().scrollEdgeAppearance = nil
    }

    // MARK: - Floating Clip Overlay

    @ViewBuilder
    private func floatingClipOverlay(clip: Clip, containerOrigin: CGPoint) -> some View {
        let size = tapesStore.floatingThumbSize
        let isHovering = hoveredTarget != nil
        let displayScale: CGFloat = isHovering ? 0.5 : 1.0
        let localPos = CGPoint(
            x: tapesStore.floatingPosition.x - containerOrigin.x,
            y: tapesStore.floatingPosition.y - containerOrigin.y
        )

        ZStack {
            if let thumbnail = clip.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Tokens.Colors.tertiaryBackground)
                    .frame(width: size.width, height: size.height)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    tapesStore.returnFloatingClip()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Tokens.Colors.primaryText)
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .offset(x: 12, y: -12)
        }
        .scaleEffect(displayScale)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovering)
        .position(localPos)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    tapesStore.floatingPosition = value.location
                }
                .onEnded { value in
                    let target = dropTargets.first {
                        $0.frame.contains(value.location) && $0.tapeID == tapesStore.jigglingTapeID
                    }
                    if let target {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            tapesStore.dropFloatingClip(onTape: target.tapeID, atIndex: target.insertionIndex, afterClipID: target.seamLeftClipID, beforeClipID: target.seamRightClipID)
                        }
                    }
                    hoveredTarget = nil
                }
        )
        .zIndex(999)
    }

    private func updateHoverTarget(at location: CGPoint) {
        let newTarget = dropTargets.first {
            $0.frame.contains(location) && $0.tapeID == tapesStore.jigglingTapeID
        }
        if newTarget != hoveredTarget {
            if newTarget != nil {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
            hoveredTarget = newTarget
        }
    }

    // MARK: - Action Handlers
    
    private func handleSettings(_ tape: Tape) {
        tapesStore.selectTape(tape)
    }
    
    private func handlePlay(_ tape: Tape) {
        tapeToPreview = tape
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
                },
                onMergeAndSave: { tape in
                    handleMergeAndSave(tape)
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
    TapesListView(showOnboarding: .constant(false))
        .environmentObject(TapesStore())
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapesListView(showOnboarding: .constant(false))
        .environmentObject(TapesStore())
        .preferredColorScheme(.light)
}
