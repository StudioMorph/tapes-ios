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
    @State private var dropTargets: [DropTargetInfo] = []
    @State private var hoveredTarget: DropTargetInfo? = nil
    @State private var showInlineTitle = false
    @State private var tapeToShare: Tape?

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
                        showInlineTitle: $showInlineTitle
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
            .onChange(of: shareUploadCoordinator.showCompletionDialog) { _, show in
                guard show,
                      shareUploadCoordinator.resultMode == .collaborating,
                      let source = shareUploadCoordinator.sourceTape,
                      let remoteId = shareUploadCoordinator.resultRemoteTapeId,
                      let shareId = shareUploadCoordinator.resultShareId else { return }

                tapesStore.forkTapeForCollaboration(
                    source,
                    remoteTapeId: remoteId,
                    shareId: shareId,
                    ownerName: authManager.userName
                )
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
                    if shareUploadCoordinator.isUploading && !shareUploadCoordinator.showProgressDialog {
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
        .sheet(item: $tapeToShare) { tape in
            ShareModalView(tape: tape)
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Tokens.Colors.primaryText)
                    .frame(width: 36, height: 36)
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

    private func handleShare(_ tape: Tape) {
        tapeToShare = tape
    }

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
            if shareUploadCoordinator.showProgressDialog {
                ShareUploadProgressDialog(coordinator: shareUploadCoordinator)
            }
            if shareUploadCoordinator.showCompletionDialog {
                ShareUploadCompletionDialog(coordinator: shareUploadCoordinator)
            }
            if shareUploadCoordinator.uploadError != nil {
                ShareUploadErrorAlert(coordinator: shareUploadCoordinator)
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
