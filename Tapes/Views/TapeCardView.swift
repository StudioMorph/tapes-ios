import SwiftUI
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

enum ImportSource {
    case leftPlaceholder
    case rightPlaceholder
    case centerFAB
}

private struct CardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}





struct TapeCardView: View {
    struct TitleEditingConfig {
        let text: Binding<String>
        let tapeID: UUID
        let onCommit: () -> Void
    }

    @Binding var tape: Tape
    let tapeID: UUID
    let tapeWidth: CGFloat
    let isLandscape: Bool
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    let onCameraCapture: (@escaping ([PickedMedia]) -> Void) -> Void
    let onTitleFocusRequest: () -> Void
    let titleEditingConfig: TitleEditingConfig?

    @EnvironmentObject var tapeStore: TapesStore
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var importCoordinator: MediaImportCoordinator
    @State private var fabMode: FABMode = .camera
    @State private var showingMediaPicker = false
    @State private var showingSeamTransition = false
    @State private var showingClipTrim = false
    @State private var clipToTrim: Clip? = nil
    @State private var showingImageSettings = false
    @State private var imageSettingsClipID: UUID? = nil
    @State private var importSource: ImportSource? = nil
    @State private var clipToDelete: Clip? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingMusicSheet = false
    @State private var showingDeleteTapeAlert = false
    @State private var showingPaywall = false
    @FocusState private var isTitleFocused: Bool
    
    // Carousel position tracking - all in clip-space
    @State private var savedCarouselPosition: Int = 0
    
    // Session flag for initial positioning
    @State private var isNewSession = true
    
    // Pending target for programmatic scroll (scoped by tape ID)
    @State private var pendingTargetItemIndex: Int? = nil
    @State private var pendingToken: UUID? = nil
    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width
    @State private var dropSeamLeftClipID: UUID? = nil
    @State private var dropSeamRightClipID: UUID? = nil
    @State private var scrollFraction: CGFloat = 0
    // Initial carousel position - set to last position in clip-space
    private var initialCarouselPosition: Int {
        return tape.clips.count // Clip-space: 0 = start, N = end
    }

    /// The pair of clip IDs straddling the current FAB position, or nil if the FAB is at start/end.
    private var seamClipIDs: (left: UUID, right: UUID)? {
        let pos = savedCarouselPosition
        guard pos >= 1, pos < tape.clips.count else { return nil }
        return (tape.clips[pos - 1].id, tape.clips[pos].id)
    }

    private var isAtSeamEnd: Bool { seamClipIDs == nil && !tape.clips.isEmpty }

    private var displayedTitle: String {
        let trimmed = tape.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? " " : trimmed
    }

    private func thumbDimensions(for width: CGFloat) -> (thumbW: CGFloat, thumbH: CGFloat) {
        let thumbW: CGFloat
        if isLandscape {
            thumbW = max(0, floor((tapeWidth / 2) - 16))
        } else {
            let availableWidth = max(0, width - Tokens.FAB.size)
            thumbW = max(0, floor(availableWidth / 2.0))
        }
        let aspectRatio: CGFloat = 9.0 / 16.0
        let thumbH = max(0, floor(thumbW * aspectRatio))
        return (thumbW, thumbH)
    }

    @ViewBuilder
    private var titleTextView: some View {
        if let config = titleEditingConfig {
            TextField("", text: config.text)
                .focused($isTitleFocused)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.headline)
                .foregroundColor(Tokens.Colors.primaryText)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                .onSubmit { config.onCommit() }
                .onAppear {
                    // Focus the field when editing starts
                    DispatchQueue.main.async {
                        isTitleFocused = true
                    }
                }
        } else {
            Text(displayedTitle)
                .font(Tokens.Typography.headline)
                .foregroundColor(Tokens.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
        }
    }

    init(
        tape: Binding<Tape>,
        tapeID: UUID,
        tapeWidth: CGFloat,
        isLandscape: Bool = false,
        onSettings: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onThumbnailDelete: @escaping (Clip) -> Void,
        onCameraCapture: @escaping (@escaping ([PickedMedia]) -> Void) -> Void = { _ in },
        onTitleFocusRequest: @escaping () -> Void = {},
        titleEditingConfig: TitleEditingConfig? = nil
    ) {
        self._tape = tape
        self.tapeID = tapeID
        self.tapeWidth = tapeWidth
        self.isLandscape = isLandscape
        self.onSettings = onSettings
        self.onPlay = onPlay
        self.onThumbnailDelete = onThumbnailDelete
        self.onCameraCapture = onCameraCapture
        self.onTitleFocusRequest = onTitleFocusRequest
        self.titleEditingConfig = titleEditingConfig
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Left group: Title (hug) + 4 + pencil
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    titleTextView
                        .onTapGesture {
                            guard titleEditingConfig == nil else { return }
                            beginEditingTitle()
                        }
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.headline)
                        .foregroundColor(Tokens.Colors.primaryText)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                        .onTapGesture {
                            guard titleEditingConfig == nil else { return }
                            beginEditingTitle()
                        }
                }
                .layoutPriority(1)
                
                // 32pt minimum gap
                Spacer(minLength: 32)
                
                // Right group: music 16 settings 16 play
                HStack(spacing: 16) {
                    HStack(spacing: 0) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "music.note")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(isEmptyTape ? Tokens.Colors.tertiaryText : Tokens.Colors.primaryText)
                    .onTapGesture { guard !isEmptyTape else { return }; showingMusicSheet = true }
                    .id("music-\(tapeID)")

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isEmptyTape ? Tokens.Colors.tertiaryText : Tokens.Colors.primaryText)
                        .onTapGesture { guard !isEmptyTape else { return }; onSettings() }
                        .id("settings-\(tapeID)")
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isEmptyTape ? Tokens.Colors.tertiaryText : Tokens.Colors.primaryText)
                        .onTapGesture { guard !isEmptyTape else { return }; onPlay() }
                        .id("play-\(tapeID)")
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.m)
            
            // Timeline container (uses container width from GeometryReader for adaptive layout)
            let (thumbW, thumbH) = thumbDimensions(for: containerWidth)
            ZStack(alignment: .center) {
                // 1) Thumbnails / scrollable carousel
                clipCarouselView(thumbW: thumbW, thumbH: thumbH)
                .zIndex(0)
                
                // 2) Red center line (between clips and FAB)
                let fabOpacity: Double = {
                    guard isJiggling, tapeStore.isFloatingClip else { return 1 }
                    let visibleCount = CGFloat(tape.clips.count - 1)
                    let clipFraction = scrollFraction - 1
                    let distFromStart = clipFraction
                    let distFromEnd = visibleCount - clipFraction
                    return Double(min(1, max(0, min(distFromStart, distFromEnd))))
                }()
                Rectangle()
                    .fill(isJiggling && tapeStore.isFloatingClip ? Tokens.Colors.tertiaryBackground : Tokens.Colors.systemRed.opacity(0.9))
                    .frame(width: 2, height: thumbH)
                    .opacity(fabOpacity)
                    .allowsHitTesting(false)
                    .zIndex(1)
                    .animation(.easeInOut(duration: 0.25), value: tapeStore.isFloatingClip)
                
                // 3) Floating action button / drop target
                if isJiggling && tapeStore.isFloatingClip {
                    dropTargetFAB(thumbH: thumbH)
                        .opacity(fabOpacity)
                        .allowsHitTesting(fabOpacity > 0.5)
                        .zIndex(2)
                } else {
                    FabSwipableIcon(
                        mode: $fabMode,
                        disabledModes: isAtSeamEnd ? [.transition] : []
                    ) {
                        if isEmptyTape && isAtFreeLimit {
                            showingPaywall = true
                            return
                        }

                        switch fabMode {
                        case .gallery:
                            importSource = .centerFAB
                            showingMediaPicker = true
                        case .camera:
                            importSource = .centerFAB
                            onCameraCapture { capturedMedia in
                                handleMediaInsertion(picked: capturedMedia, source: .centerFAB)
                            }
                        case .transition:
                            if seamClipIDs != nil {
                                showingSeamTransition = true
                            }
                        }
                    }
                    .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
                    .zIndex(2)
                    .onChange(of: isAtSeamEnd) { _, atEnd in
                        if atEnd && fabMode == .transition {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                fabMode = .camera
                            }
                        }
                    }
                }
            }
            
            .frame(height: thumbH)

            .padding(.vertical, Tokens.Spacing.m)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: CardWidthKey.self, value: geometry.size.width)
                }
            )
            .onPreferenceChange(CardWidthKey.self) { width in
                if width > 0 { containerWidth = width }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.secondaryBackground)
        )
        .onTapGesture {
            if isJiggling { exitJiggleMode() }
        }
        .onChange(of: tapeStore.isFloatingClip) { _, isFloating in
            if isFloating {
                pendingTargetItemIndex = nil
                pendingToken = nil
                let visibleClips = tape.clips.filter { $0.id != tapeStore.floatingClip?.id }
                let floatingBefore = tapeStore.floatingSourceIndex.map { $0 < savedCarouselPosition } ?? false
                scrollFraction = CGFloat(savedCarouselPosition + 1 - (floatingBefore ? 1 : 0))
                let seamPos = savedCarouselPosition - (floatingBefore ? 1 : 0)
                dropSeamLeftClipID = (seamPos >= 1 && seamPos - 1 < visibleClips.count) ? visibleClips[seamPos - 1].id : nil
                dropSeamRightClipID = (seamPos >= 0 && seamPos < visibleClips.count) ? visibleClips[seamPos].id : nil
                TapesLog.ui.debug("Seam lift: savedPos=\(savedCarouselPosition) seamPos=\(seamPos)")
            } else {
                dropSeamLeftClipID = nil
                dropSeamRightClipID = nil
            }
        }
        .onChange(of: tapeStore.dropCompletedTapeID) { _, newID in
            guard newID == tape.id,
                  let dropIndex = tapeStore.dropCompletedAtIndex else { return }
            savedCarouselPosition = dropIndex
            let token = UUID()
            pendingToken = token
            pendingTargetItemIndex = dropIndex + 1
            tapeStore.dropCompletedTapeID = nil
            tapeStore.dropCompletedAtIndex = nil
        }
        .onAppear {
            if isNewSession {
                savedCarouselPosition = initialCarouselPosition
            }
        }
        .sheet(isPresented: $showingMediaPicker) {
            SystemMediaPicker(
                isPresented: $showingMediaPicker,
                allowImages: true,
                allowVideos: true
            ) { results in
                TapesLog.mediaPicker.info("🧩 onPick count=\(results.count, privacy: .public)")
                guard !results.isEmpty else { return }

                let insertionIndex: Int
                switch importSource {
                case .leftPlaceholder:
                    insertionIndex = 0
                case .rightPlaceholder:
                    insertionIndex = tape.clips.count
                case .centerFAB, .none:
                    insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                }
                importSource = nil

                importCoordinator.startImport(
                    results: results,
                    tapeID: tape.id,
                    insertionIndex: insertionIndex
                )
            }
        }
        .onChange(of: importCoordinator.isImporting) { _, isImporting in
            if !isImporting, let result = importCoordinator.consumeResults(for: tape.id) {
                let pSnapshot = savedCarouselPosition
                tapeStore.insert(result.clips, into: result.tapeID, at: result.insertionIndex)
                tapeStore.associateClipsWithAlbum(tapeID: result.tapeID, clips: result.clips)

                let pAfter = pSnapshot + result.clips.count
                let targetItemIndex = pAfter + 1
                let token = UUID()
                pendingToken = token
                pendingTargetItemIndex = targetItemIndex

                checkAndCreateEmptyTapeIfNeeded()
            }
        }
        .sheet(isPresented: $showingSeamTransition) {
            if let ids = seamClipIDs {
                SeamTransitionView(
                    tape: $tape,
                    leftClipID: ids.left,
                    rightClipID: ids.right,
                    onDismiss: { showingSeamTransition = false }
                )
            }
        }
        .fullScreenCover(isPresented: $showingClipTrim) {
            if let clipToTrim,
               let clipIndex = tape.clips.firstIndex(where: { $0.id == clipToTrim.id }) {
                ClipTrimView(
                    clip: $tape.clips[clipIndex],
                    tape: tape,
                    onDismiss: {
                        showingClipTrim = false
                        self.clipToTrim = nil
                    },
                    onSave: { updatedClip in
                        tape.updateClip(updatedClip)
                        tapeStore.updateTape(tape)
                    }
                )
            }
        }
        .sheet(isPresented: $showingImageSettings) {
            if let clipID = imageSettingsClipID {
                ImageClipSettingsView(
                    tape: $tape,
                    clipID: clipID,
                    onDismiss: {
                        showingImageSettings = false
                        imageSettingsClipID = nil
                    }
                )
                .environmentObject(tapeStore)
            }
        }
        .alert("Delete Clip?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteClipFromTape()
            }
            Button("Cancel", role: .cancel) {
                clipToDelete = nil
            }
        } message: {
            Text("This will remove the clip from the tape. The photo or video will remain in your library.")
        }
        .alert("Delete this Tape?", isPresented: $showingDeleteTapeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                tapeStore.deleteTape(tape)
            }
        } message: {
            Text("This will delete the Tape and its album. Your photos and videos remain in your device's Library.")
        }
        .sheet(isPresented: $showingMusicSheet) {
            BackgroundMusicView(tape: $tape)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
    
    // MARK: - Jiggle Mode

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID == tape.id
    }

    private func enterJiggleMode() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        tapeStore.jigglingTapeID = tape.id
    }

    private func exitJiggleMode() {
        if tapeStore.isFloatingClip {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                tapeStore.returnFloatingClip()
            }
        }
        tapeStore.jigglingTapeID = nil
    }

    private func duplicateClip(_ clip: Clip) {
        guard let sourceIndex = tape.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        var copy = clip
        let newID = UUID()
        copy.id = newID
        copy.createdAt = Date()
        copy.updatedAt = Date()

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mediaDir = docs.appendingPathComponent("clip_media", isDirectory: true)

        let thumbSrc = mediaDir.appendingPathComponent("\(clip.id)_thumb.jpg")
        let thumbDst = mediaDir.appendingPathComponent("\(newID)_thumb.jpg")
        try? fm.copyItem(at: thumbSrc, to: thumbDst)

        let imageSrc = mediaDir.appendingPathComponent("\(clip.id)_image.dat")
        let imageDst = mediaDir.appendingPathComponent("\(newID)_image.dat")
        try? fm.copyItem(at: imageSrc, to: imageDst)

        tapeStore.addClip(to: tape.id, clip: copy, at: sourceIndex + 1)
        if let updated = tapeStore.getTape(by: tape.id) {
            tape = updated
        }

        let newPosition = sourceIndex + 2
        savedCarouselPosition = newPosition
        let token = UUID()
        pendingToken = token
        pendingTargetItemIndex = newPosition + 1
    }

    private func deleteClipFromTape() {
        guard let clip = clipToDelete else { return }
        let deletedIndex = tape.clips.firstIndex(where: { $0.id == clip.id })
        tapeStore.deleteClip(from: tape.id, clip: clip)
        if let updated = tapeStore.getTape(by: tape.id) {
            tape = updated
        }
        clipToDelete = nil

        if let idx = deletedIndex, idx < savedCarouselPosition {
            savedCarouselPosition = max(0, savedCarouselPosition - 1)
        }
        savedCarouselPosition = min(savedCarouselPosition, tape.clips.count)

        pendingTargetItemIndex = nil
        pendingToken = nil

        if tape.clips.isEmpty {
            exitJiggleMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
                showingDeleteTapeAlert = true
            }
        }
    }

    @ViewBuilder
    private func clipCarouselView(thumbW: CGFloat, thumbH: CGFloat) -> some View {
        ClipCarousel(
            tape: $tape,
            thumbSize: CGSize(width: thumbW, height: thumbH),
            savedCarouselPosition: $savedCarouselPosition,
            isNewSession: $isNewSession,
            initialCarouselPosition: initialCarouselPosition,
            pendingTargetItemIndex: $pendingTargetItemIndex,
            pendingToken: $pendingToken,
            onPlaceholderTap: handlePlaceholderTap,
            onJiggleRequested: {
                guard !tape.clips.isEmpty else { return }
                enterJiggleMode()
            },
            onClipTap: handleClipTap,
            onClipDelete: handleClipDelete,
            onClipDuplicate: duplicateClip,
            onSeamChanged: handleSeamChanged,
            onScrollFractionChanged: { fraction in
                scrollFraction = fraction
            }
        )
    }

    private func handlePlaceholderTap(_ item: CarouselItem) {
        guard !isJiggling else {
            exitJiggleMode()
            return
        }

        if isEmptyTape && isAtFreeLimit {
            showingPaywall = true
            return
        }

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

    private func handleClipTap(_ clip: Clip) {
        guard !clip.isPlaceholder else { return }
        if isJiggling { return }
        if clip.clipType == .video {
            clipToTrim = clip
            showingClipTrim = true
        } else if clip.clipType == .image {
            imageSettingsClipID = clip.id
            showingImageSettings = true
        }
    }

    private func handleClipDelete(_ clip: Clip) {
        clipToDelete = clip
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingDeleteConfirmation = true
        }
    }

    private func handleSeamChanged(_ leftID: UUID?, _ rightID: UUID?) {
        if tapeStore.isFloatingClip {
            dropSeamLeftClipID = leftID
            dropSeamRightClipID = rightID
        }
    }

    // MARK: - Drop Target FAB

    @ViewBuilder
    private func dropTargetFAB(thumbH: CGFloat) -> some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Circle()
                .fill(Tokens.Colors.tertiaryBackground)
                .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .overlay {
                    photoStackDashedIcon()
                }
                .preference(key: DropTargetPreferenceKey.self, value: [
                    DropTargetInfo(tapeID: tape.id, insertionIndex: savedCarouselPosition, seamLeftClipID: dropSeamLeftClipID, seamRightClipID: dropSeamRightClipID, frame: frame, kind: .fab)
                ])
        }
        .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
    }

    private func photoStackDashedIcon() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Tokens.Colors.primaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 28, height: 28)
            Image(systemName: "photo.stack")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Tokens.Colors.primaryText)
        }
    }

    // MARK: - Helper Functions
    
    /// Handle media insertion from camera or other sources
    private func handleMediaInsertion(picked: [PickedMedia], source: ImportSource) {
        guard !picked.isEmpty else { return }
        
        Task {
            await MainActor.run {
                // Capture current position in clip-space before insertion
                let pSnapshot = savedCarouselPosition
                let k = picked.count
                
                let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                insertClipsAtPosition(picked: picked, at: insertionIndex, into: $tape)
                
                // Calculate target position in clip-space after insertion
                let pAfter = pSnapshot + k
                let targetItemIndex = pAfter + 1 // Convert to item-space (+1 for start-plus)
                
                // Generate monotonic token for this operation
                let token = UUID()
                pendingToken = token
                pendingTargetItemIndex = targetItemIndex
                
                // First-content side effect: create new empty tape if this was the first content
                checkAndCreateEmptyTapeIfNeeded()
            }
        }
    }
    
    /// Calculate the insertion index based on carousel position (clip-space)
    private func calculateInsertionIndex(from carouselPosition: Int, tape: Tape) -> Int {
        // carouselPosition is in clip-space: 0 = start, N = end
        // Convert to clip insertion index
        let insertionIndex = max(0, min(carouselPosition, tape.clips.count))
        return insertionIndex
    }
    
    private func makeClips(from picked: [PickedMedia]) -> [Clip] {
        var clips: [Clip] = []
        for item in picked {
            switch item {
            case let .video(url, duration, assetIdentifier):
                let clip = makeVideoClip(url: url, duration: duration, assetIdentifier: assetIdentifier)
                clips.append(clip)
            case let .photo(image, assetIdentifier, _):
                if let clip = makeImageClip(image: image, assetIdentifier: assetIdentifier) {
                    clips.append(clip)
                }
            }
        }
        return clips
    }

    private func makeVideoClip(url: URL?, duration: TimeInterval, assetIdentifier: String?) -> Clip {
        var clip = Clip(
            assetLocalId: assetIdentifier,
            localURL: url,
            clipType: .video,
            duration: duration,
            thumbnail: nil
        )
        clip.updatedAt = Date()
        return clip
    }

    private func makeImageClip(image: UIImage, assetIdentifier: String?) -> Clip? {
        let thumb = image.preparingThumbnail(of: CGSize(width: 480, height: 480))
        let thumbnailData = (thumb ?? image).jpegData(compressionQuality: 0.8)
        let imageData: Data?
        if assetIdentifier == nil {
            imageData = image.jpegData(compressionQuality: 0.85)
        } else {
            imageData = nil
        }

        if assetIdentifier != nil || imageData != nil {
            var clip = Clip(
                assetLocalId: assetIdentifier,
                imageData: imageData,
                clipType: .image,
                duration: Tokens.Timing.photoDefaultDuration,
                thumbnail: thumbnailData
            )
            clip.updatedAt = Date()
            return clip
        }
        return nil
    }
    
    /// Insert clips at a specific position in the tape
    private func insertClipsAtPosition(picked: [PickedMedia], at index: Int, into tape: Binding<Tape>) {
        let newClips = makeClips(from: picked)
        guard !newClips.isEmpty else { return }
        
        // Insert clips at the calculated position
        var updatedTape = tape.wrappedValue
        let insertIndex = max(0, min(index, updatedTape.clips.count))
        updatedTape.clips.insert(contentsOf: newClips, at: insertIndex)
        updatedTape.updatedAt = Date()
        tape.wrappedValue = updatedTape
        tapeStore.updateTape(updatedTape)        
        tapeStore.associateClipsWithAlbum(tapeID: updatedTape.id, clips: newClips)
        // Generate thumbnails and duration for video clips asynchronously
        for clip in newClips where clip.clipType == .video {
            tapeStore.generateThumbAndDuration(for: clip, tapeID: updatedTape.id)
        }
    }
    

    /// Check if this tape just received its first content and create new empty tape if needed.
    private func checkAndCreateEmptyTapeIfNeeded() {
        guard tape.clips.count > 0, !tape.hasReceivedFirstContent else { return }
        var updated = tape
        updated.hasReceivedFirstContent = true
        tapeStore.updateTape(updated)

        tapeStore.insertEmptyTapeAtTop()
    }

    private var isEmptyTape: Bool {
        tape.clips.isEmpty && !tape.hasReceivedFirstContent
    }

    private var isAtFreeLimit: Bool {
        !entitlementManager.canCreateTape(currentCount: tapeStore.contentTapeCount)
    }

    private func beginEditingTitle() {
        guard titleEditingConfig == nil else { return }
        if isEmptyTape && isAtFreeLimit {
            showingPaywall = true
            return
        }
        onTitleFocusRequest()
    }

}

#Preview {
    TapeCardView(
        tape: Binding.constant(Tape.sampleTapes[0]),
        tapeID: Tape.sampleTapes[0].id,
        tapeWidth: 375,
        isLandscape: false,
        onSettings: {},
        onPlay: {},
        onThumbnailDelete: { _ in },
        onCameraCapture: { _ in },
        onTitleFocusRequest: {},
        titleEditingConfig: nil
    )
    .environmentObject(TapesStore())
    .environmentObject(EntitlementManager())
    .environmentObject(MediaImportCoordinator())
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
