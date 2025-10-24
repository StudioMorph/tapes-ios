import SwiftUI
import AVFoundation
import PhotosUI


struct TapeTitleEditOverlay: View {
    let state: TapeEditOverlayState
    let keyboardHeight: CGFloat
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    
    @State private var draftTitle: String
    @State private var currentPoint: CGPoint = .zero
    @State private var startPoint: CGPoint = .zero
    @State private var targetPoint: CGPoint = .zero
    @FocusState private var isFocused: Bool
    
    init(state: TapeEditOverlayState, keyboardHeight: CGFloat, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.state = state
        self.keyboardHeight = keyboardHeight
        self.onCommit = onCommit
        self.onCancel = onCancel
        _draftTitle = State(initialValue: state.tape.title)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss(commit: false) }
                EditableTapeCardView(
                    tape: state.binding,
                    title: $draftTitle,
                    actions: state.actions,
                    isFocused: _isFocused,
                    onDone: { dismiss(commit: true) }
                )
                .frame(width: max(state.frame.width, geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing + 40))
                .offset(x: currentPoint.x, y: currentPoint.y)
                .onAppear {
                    let containerOrigin = geo.frame(in: .global).origin
                    let start = CGPoint(
                        x: state.frame.minX - containerOrigin.x,
                        y: state.frame.minY - containerOrigin.y
                    )
                    let target = targetPosition(in: geo, containerOrigin: containerOrigin, start: start)
                    startPoint = start
                    targetPoint = target
                    currentPoint = start
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        currentPoint = target
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isFocused = true
                    }
                }
                .onChange(of: keyboardHeight) { _ in
                    let containerOrigin = geo.frame(in: .global).origin
                    let start = CGPoint(
                        x: state.frame.minX - containerOrigin.x,
                        y: state.frame.minY - containerOrigin.y
                    )
                    let target = targetPosition(in: geo, containerOrigin: containerOrigin, start: start)
                    targetPoint = target
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        currentPoint = target
                    }
                }
            }
        }
    }
    
    private func targetPosition(in geo: GeometryProxy, containerOrigin: CGPoint, start: CGPoint) -> CGPoint {
        let availableHeight = geo.size.height - keyboardHeight
        let safeTop = geo.safeAreaInsets.top + 16
        let maxTop = max(safeTop, availableHeight - state.frame.height - 16)
        let centerCandidate = safeTop + max(0, (availableHeight - state.frame.height) / 2)
        let clampedY = min(max(safeTop, centerCandidate), maxTop)

        let clampedX = min(max(start.x + containerOrigin.x, geo.safeAreaInsets.leading + 16), geo.size.width - geo.safeAreaInsets.trailing - state.frame.width - 16)
        return CGPoint(x: clampedX - containerOrigin.x, y: clampedY - containerOrigin.y)
    }
    
    private func dismiss(commit: Bool) {
        isFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentPoint = startPoint
        }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if commit {
                onCommit(trimmed)
            } else {
                onCancel()
            }
        }
    }
}

private struct EditableTapeCardView: View {
    @Binding var tape: Tape
    @Binding var title: String
    let actions: TapeEditOverlayState.Actions
    @FocusState var isFocused: Bool
    let onDone: () -> Void
    
    @EnvironmentObject var tapeStore: TapesStore
    @StateObject private var castManager = CastManager.shared
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @State private var insertionIndex: Int = 0
    @State private var fabMode: FABMode = .camera
    @State private var showingMediaPicker = false
    @State private var importSource: ImportSource? = nil
    @State private var savedCarouselPosition: Int = 0
    @State private var pendingAdvancement: Int = 0
    @State private var isNewSession = true
    @State private var pendingTargetItemIndex: Int? = nil
    @State private var pendingToken: UUID? = nil
    
    private var initialCarouselPosition: Int {
        tape.clips.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("", text: $title)
                        .focused($isFocused)
                        .textFieldStyle(.plain)
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit { onDone() }
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 32)
                
                HStack(spacing: 16) {
                    Button(action: actions.onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                    Button(action: actions.onAirPlay) {
                        Image(systemName: "airplayvideo")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                    Button(action: actions.onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.m)
            
            let screenW = UIScreen.main.bounds.width
            let availableWidth = max(0, screenW - Tokens.FAB.size)
            let thumbW = max(0, floor(availableWidth / 2.0))
            let aspectRatio: CGFloat = 9.0 / 16.0
            let thumbH = max(0, floor(thumbW * aspectRatio))
            
            ZStack(alignment: .center) {
                ClipCarousel(
                    tape: $tape,
                    thumbSize: CGSize(width: thumbW, height: thumbH),
                    insertionIndex: $insertionIndex,
                    savedCarouselPosition: $savedCarouselPosition,
                    pendingAdvancement: $pendingAdvancement,
                    isNewSession: $isNewSession,
                    initialCarouselPosition: initialCarouselPosition,
                    pendingTargetItemIndex: $pendingTargetItemIndex,
                    pendingToken: $pendingToken,
                    onPlaceholderTap: { item in
                        switch item {
                        case .startPlus:
                            importSource = .leftPlaceholder
                        case .endPlus:
                            importSource = .rightPlaceholder
                        case .clip:
                            importSource = .centerFAB
                        }
                        showingMediaPicker = true
                    }
                )
                .id("overlay-carousel-\(tape.clips.count)")
                .zIndex(0)
                
                Rectangle()
                    .fill(Tokens.Colors.red.opacity(0.9))
                    .frame(width: 2, height: thumbH)
                    .allowsHitTesting(false)
                    .zIndex(1)
                
                FabSwipableIcon(mode: $fabMode) {
                    switch fabMode {
                    case .gallery:
                        importSource = .centerFAB
                        showingMediaPicker = true
                    case .camera:
                        importSource = .centerFAB
                        cameraCoordinator.presentCamera { capturedMedia in
                            handleMediaInsertion(picked: capturedMedia, source: .centerFAB)
                        }
                    case .transition:
                        break
                    }
                }
                .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
                .zIndex(2)
            }
            .frame(height: thumbH)
            .padding(.vertical, Tokens.Spacing.m)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.card)
        )
        .sheet(isPresented: $showingMediaPicker) {
            SystemMediaPicker(
                isPresented: $showingMediaPicker,
                allowImages: true,
                allowVideos: true
            ) { results in
                TapesLog.mediaPicker.info("🧩 onPick count=\(results.count, privacy: .public)")
                guard !results.isEmpty else { return }

                Task {
                    let picked = await resolvePickedMediaOrdered(results)
                    TapesLog.mediaPicker.info("📦 converted count=\(picked.count, privacy: .public)")
                    guard !picked.isEmpty else { return }

                    await MainActor.run {
                        let pSnapshot = savedCarouselPosition
                        let k = picked.count

                        switch importSource {
                        case .leftPlaceholder:
                            insertClipsAtPosition(picked: picked, at: 0)
                        case .rightPlaceholder:
                            insertClipsAtPosition(picked: picked, at: tape.clips.count)
                        case .centerFAB, .none:
                            let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                            insertClipsAtPosition(picked: picked, at: insertionIndex)
                        }

                        let pAfter = pSnapshot + k
                        let targetItemIndex = pAfter + 1
                        let token = UUID()
                        pendingToken = token
                        pendingTargetItemIndex = targetItemIndex
                        checkAndCreateEmptyTapeIfNeeded()
                        importSource = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $cameraCoordinator.isPresented) {
            CameraView(coordinator: cameraCoordinator)
                .ignoresSafeArea(.all, edges: .all)
        }
    }
    
    private func handleMediaInsertion(picked: [PickedMedia], source: ImportSource) {
        guard !picked.isEmpty else { return }
        Task {
            await MainActor.run {
                let pSnapshot = savedCarouselPosition
                let k = picked.count

                switch source {
                case .centerFAB:
                    let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                    insertClipsAtPosition(picked: picked, at: insertionIndex)
                default:
                    let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                    insertClipsAtPosition(picked: picked, at: insertionIndex)
                }

                let pAfter = pSnapshot + k
                let targetItemIndex = pAfter + 1
                let token = UUID()
                pendingToken = token
                pendingTargetItemIndex = targetItemIndex
                checkAndCreateEmptyTapeIfNeeded()
            }
        }
    }
    
    private func calculateInsertionIndex(from carouselPosition: Int, tape: Tape) -> Int {
        let insertionIndex = max(0, min(carouselPosition, tape.clips.count))
        return insertionIndex
    }
    
    private func insertClipsAtPosition(picked: [PickedMedia], at index: Int) {
        let newClips = makeClips(from: picked)
        guard !newClips.isEmpty else { return }
        var updatedTape = tape
        let insertIndex = max(0, min(index, updatedTape.clips.count))
        updatedTape.clips.insert(contentsOf: newClips, at: insertIndex)
        updatedTape.updatedAt = Date()
        tape = updatedTape
        tapeStore.updateTape(updatedTape)
        tapeStore.associateClipsWithAlbum(tapeID: updatedTape.id, clips: newClips)
        for clip in newClips {
            if clip.clipType == .video, let url = clip.localURL {
                tapeStore.generateThumbAndDuration(for: url, clipID: clip.id, tapeID: updatedTape.id)
            }
        }
    }
    
    private func makeClips(from picked: [PickedMedia]) -> [Clip] {
        var clips: [Clip] = []
        for item in picked {
            switch item {
            case let .video(url, duration, assetIdentifier):
                var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
                if clip.duration <= 0 {
                    let asset = AVURLAsset(url: url)
                    let seconds = CMTimeGetSeconds(asset.duration)
                    if seconds > 0 {
                        clip.duration = seconds
                    }
                }
                clips.append(clip)
            case let .photo(image, assetIdentifier):
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    clips.append(
                        Clip.fromImage(
                            imageData: imageData,
                            duration: Tokens.Timing.photoDefaultDuration,
                            thumbnail: image,
                            assetLocalId: assetIdentifier
                        )
                    )
                }
            }
        }
        return clips
    }
    
    
    private func checkAndCreateEmptyTapeIfNeeded() {
        if tape.clips.count > 0 && !tape.hasReceivedFirstContent {
            tape.hasReceivedFirstContent = true
            tapeStore.insertEmptyTapeAtTop()
        }
    }
}
