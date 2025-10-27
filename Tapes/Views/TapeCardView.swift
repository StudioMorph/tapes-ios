import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum ImportSource {
    case leftPlaceholder
    case rightPlaceholder
    case centerFAB
}





struct TapeCardView: View {
    struct TitleEditingConfig {
        let text: Binding<String>
        let tapeID: UUID
        let onCommit: () -> Void
    }

    @Binding var tape: Tape
    let tapeID: UUID
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    
    let onClipInserted: (Clip, Int) -> Void
    let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void
    let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void
    let onTitleFocusRequest: () -> Void
    let titleEditingConfig: TitleEditingConfig?

    @EnvironmentObject var tapeStore: TapesStore
    @StateObject private var castManager = CastManager.shared
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @State private var insertionIndex: Int = 0
    @State private var fabMode: FABMode = .camera
    @State private var showingMediaPicker = false
    @State private var importSource: ImportSource? = nil
    @FocusState private var isTitleFocused: Bool
    
    // Carousel position tracking - all in clip-space
    @State private var savedCarouselPosition: Int = 0 // Clip-space position (0 = start, N = end)
    @State private var pendingAdvancement: Int = 0 // How many positions to advance after insertion (clip-space)
    
    // Session flag for initial positioning
    @State private var isNewSession = true
    
    // Pending target for programmatic scroll (scoped by tape ID)
    @State private var pendingTargetItemIndex: Int? = nil
    @State private var pendingToken: UUID? = nil
    // Initial carousel position - set to last position in clip-space
    private var initialCarouselPosition: Int {
        return tape.clips.count // Clip-space: 0 = start, N = end
    }

    private var displayedTitle: String {
        let trimmed = tape.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? " " : trimmed
    }

    @ViewBuilder
    private var titleTextView: some View {
        if let config = titleEditingConfig {
            TextField("", text: config.text)
                .focused($isTitleFocused)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.onSurface)
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
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.onSurface)
                .lineLimit(1)
                .truncationMode(.tail)
                .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
        }
    }

    init(
        tape: Binding<Tape>,
        tapeID: UUID,
        onSettings: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onAirPlay: @escaping () -> Void,
        onThumbnailDelete: @escaping (Clip) -> Void,
        onClipInserted: @escaping (Clip, Int) -> Void,
        onClipInsertedAtPlaceholder: @escaping (Clip, CarouselItem) -> Void,
        onMediaInserted: @escaping ([PickedMedia], InsertionStrategy) -> Void,
        onTitleFocusRequest: @escaping () -> Void = {},
        titleEditingConfig: TitleEditingConfig? = nil
    ) {
        self._tape = tape
        self.tapeID = tapeID
        self.onSettings = onSettings
        self.onPlay = onPlay
        self.onAirPlay = onAirPlay
        self.onThumbnailDelete = onThumbnailDelete
        self.onClipInserted = onClipInserted
        self.onClipInsertedAtPlaceholder = onClipInsertedAtPlaceholder
        self.onMediaInserted = onMediaInserted
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
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                        .onTapGesture {
                            guard titleEditingConfig == nil else { return }
                            beginEditingTitle()
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard titleEditingConfig == nil else { return }
                    beginEditingTitle()
                }
                .layoutPriority(1)
                
                // 32pt minimum gap
                Spacer(minLength: 32)
                
                // Right group: gear 16 cast? 16 play
                HStack(spacing: 16) {
                    // Settings button
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                    
                    // AirPlay button (only show if available devices)
                    if castManager.hasAvailableDevices {
                        Button(action: onAirPlay) {
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Tokens.Colors.onSurface)
                        }
                    }
                    
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.m)
            
            // Timeline container
            let screenW = UIScreen.main.bounds.width
            let availableWidth = max(0, screenW - Tokens.FAB.size)
            let thumbW = max(0, floor(availableWidth / 2.0))
            let aspectRatio: CGFloat = 9.0 / 16.0
            let thumbH = max(0, floor(thumbW * aspectRatio))
            
            
            ZStack(alignment: .center) {
                // 1) Thumbnails / scrollable carousel
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
                        // Store import source and show picker
                        switch item {
                        case .startPlus:
                            importSource = .leftPlaceholder
                        case .endPlus:
                            importSource = .rightPlaceholder
                        case .clip:
                            importSource = .centerFAB // Fallback
                        }
                        showingMediaPicker = true
                    }
                )
                .id("carousel-\(tape.clips.count)") // Force view update when clips change
                .zIndex(0) // always behind the line and FAB
                
                // 2) Red center line (between clips and FAB)
                Rectangle()
                    .fill(Tokens.Colors.red.opacity(0.9))
                    .frame(width: 2, height: thumbH)
                    .allowsHitTesting(false)
                    .zIndex(1) // above thumbnails, below FAB
                
                // 3) Floating action button (camera)
                FabSwipableIcon(mode: $fabMode) {
                    // Handle FAB tap action based on mode
                    switch fabMode {
                    case .gallery:
                        importSource = .centerFAB
                        showingMediaPicker = true
                    case .camera:
                        // Launch native camera
                        importSource = .centerFAB
                        cameraCoordinator.presentCamera { capturedMedia in
                            handleMediaInsertion(picked: capturedMedia, source: .centerFAB)
                        }
                    case .transition:
                        // Handle transition action
                        break
                    }
                }
                .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
                .zIndex(2) // on top of everything
            }
            .overlay(alignment: .topLeading) {
                if let progress = tapeStore.batchProgress(for: tape.id),
                   progress.inProgress > 0 || progress.failed > 0 {
                    BatchProgressChip(progress: progress)
                        .padding(.leading, Tokens.Spacing.m)
                        .padding(.top, Tokens.Spacing.s)
                }
            }
            .frame(height: thumbH)
            .padding(.vertical, Tokens.Spacing.m)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.card)
        )
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

                Task {
                    let tapeID = tape.id
                    var placeholderIDs: [UUID] = []
                    await MainActor.run {
                        let pSnapshot = savedCarouselPosition
                        let insertionIndex: Int
                        switch importSource {
                        case .leftPlaceholder:
                            insertionIndex = 0
                        case .rightPlaceholder:
                            insertionIndex = tape.clips.count
                        case .centerFAB, .none:
                            insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                        }
                        placeholderIDs = tapeStore.insertPlaceholderClips(
                            count: results.count,
                            into: tapeID,
                            at: insertionIndex
                        )
                        let k = results.count
                        let pAfter = pSnapshot + k
                        let targetItemIndex = pAfter + 1
                        let token = UUID()
                        pendingToken = token
                        pendingTargetItemIndex = targetItemIndex
                        checkAndCreateEmptyTapeIfNeeded()
                        importSource = nil
                    }
                    if !placeholderIDs.isEmpty {
                        tapeStore.processPickerResults(results, placeholderIDs: placeholderIDs, tapeID: tapeID)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $cameraCoordinator.isPresented) {
            CameraView(coordinator: cameraCoordinator)
                .ignoresSafeArea(.all, edges: .all)
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
                
                // Insert media based on source
                switch source {
                case .centerFAB:
                    // Insert at current carousel position (where FAB is positioned)
                    let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                    insertClipsAtPosition(picked: picked, at: insertionIndex, into: $tape)
                default:
                    let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                    insertClipsAtPosition(picked: picked, at: insertionIndex, into: $tape)
                }
                
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
        for clip in newClips {
            if clip.clipType == .video, let url = clip.localURL {
                tapeStore.generateThumbAndDuration(for: url, clipID: clip.id, tapeID: updatedTape.id)
            }
        }
    }
    

    /// Check if this tape just received its first content and create new empty tape if needed
    private func checkAndCreateEmptyTapeIfNeeded() {
        // Check if tape just transitioned from 0 → >0 clips and hasReceivedFirstContent == false
        if tape.clips.count > 0 && !tape.hasReceivedFirstContent {
            // Set hasReceivedFirstContent = true on this tape and persist
            tape.hasReceivedFirstContent = true
            
            // Insert a new empty tape at index 0
            tapeStore.insertEmptyTapeAtTop()
            
            }
    }

    private func beginEditingTitle() {
        guard titleEditingConfig == nil else { return }
        onTitleFocusRequest()
    }

}

private struct BatchProgressChip: View {
    let progress: ClipBatchProgress
    
    private var label: String {
        if progress.failed > 0 && progress.inProgress > 0 {
            return "\(progress.ready)/\(progress.total) ready • \(progress.failed) failed"
        } else if progress.failed > 0 {
            return "\(progress.failed) failed"
        } else {
            return "Importing \(progress.ready)/\(progress.total)"
        }
    }
    
    private var backgroundColor: Color {
        Tokens.Colors.card.opacity(0.94)
    }
    
    @ViewBuilder
    private var leadingIcon: some View {
        if progress.failed > 0 {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 14, weight: .semibold))
        } else if progress.inProgress > 0 {
            ProgressView()
                .controlSize(.small)
                .tint(Tokens.Colors.onSurface)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14, weight: .semibold))
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            leadingIcon
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Tokens.Colors.onSurface)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(backgroundColor)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
    }
}

#Preview("Dark Mode") {
    TapeCardView(
        tape: Binding.constant(Tape.sampleTapes[0]),
        tapeID: Tape.sampleTapes[0].id,
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in },
        onClipInserted: { _, _ in },
        onClipInsertedAtPlaceholder: { _, _ in },
        onMediaInserted: { _, _ in }
    )
    .environmentObject(TapesStore())  // lightweight preview store
    .preferredColorScheme(ColorScheme.dark)
    .padding()
    .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    TapeCardView(
        tape: Binding.constant(Tape.sampleTapes[0]),
        tapeID: Tape.sampleTapes[0].id,
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in },
        onClipInserted: { _, _ in },
        onClipInsertedAtPlaceholder: { _, _ in },
        onMediaInserted: { _, _ in }
    )
    .environmentObject(TapesStore())  // lightweight preview store
    .preferredColorScheme(ColorScheme.light)
    .padding()
    .background(Tokens.Colors.bg)
}
