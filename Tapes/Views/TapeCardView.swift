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
    @Binding var tape: Tape
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    
    let onClipInserted: (Clip, Int) -> Void
    let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void
    let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void
    
    @EnvironmentObject var tapeStore: TapesStore
    @StateObject private var castManager = CastManager.shared
    @StateObject private var cameraCoordinator = CameraCoordinator()
    @State private var insertionIndex: Int = 0
    @State private var fabMode: FABMode = .camera
    @State private var showingMediaPicker = false
    @State private var importSource: ImportSource? = nil
    @State private var titleDraft: String = ""
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
        let source = isTitleFocused ? titleDraft : tape.title
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? " " : trimmed
    }
    
    var body: some View {        VStack(alignment: .leading, spacing: 0) {
            // Title row
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Left group: Title (hug) + 4 + pencil
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayedTitle)
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                        .opacity(isTitleFocused ? 0 : 1)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                TextField("", text: $titleDraft)
                                    .focused($isTitleFocused)
                                    .textFieldStyle(.plain)
                                    .font(Tokens.Typography.title)
                                    .foregroundColor(Tokens.Colors.onSurface)
                                    .disableAutocorrection(true)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .submitLabel(.done)
                                    .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                                    .frame(width: proxy.size.width, alignment: .leading)
                                    .clipped()
                                    .opacity(isTitleFocused ? 1 : 0)
                                    .allowsHitTesting(isTitleFocused)
                                    .onSubmit {
                                        commitTitle()
                                        isTitleFocused = false
                                    }
                                    .onChange(of: tape.title) { _ in
                                        syncTitleDraftIfNeeded()
                                    }
                                    .onChange(of: isTitleFocused) { focused in
                                        if !focused {
                                            commitTitle()
                                        }
                                    }
                            }
                        }
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                        .onTapGesture {
                            beginEditingTitle()
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isTitleFocused else { return }
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
                    let picked = await resolvePickedMediaOrdered(results)
                    TapesLog.mediaPicker.info("📦 converted count=\(picked.count, privacy: .public)")
                    guard !picked.isEmpty else { return }

                    await MainActor.run {
                        // Capture current position in clip-space before insertion
                        let pSnapshot = savedCarouselPosition
                        let k = picked.count
                        
                        // Route insertion through the boundary currently under the FAB
                        switch importSource {
                        case .leftPlaceholder:
                            insertClipsAtPosition(picked: picked, at: 0, into: $tape)
                        case .rightPlaceholder:
                            insertClipsAtPosition(picked: picked, at: tape.clips.count, into: $tape)
                        case .centerFAB, .none:
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
                        
                        // Reset import source
                        importSource = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $cameraCoordinator.isPresented) {
            CameraView(coordinator: cameraCoordinator)
                .ignoresSafeArea(.all, edges: .all)
        }
        .onAppear {
            syncTitleDraftIfNeeded(force: true)
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
    

    private func processPickerResults(_ results: [PHPickerResult]) async -> [PickedMedia] {
        var pickedMedia: [PickedMedia] = []
        
        for result in results {
            do {
                // Try to load as video first
                let movie = try await withCheckedThrowingContinuation { continuation in
                    result.itemProvider.loadTransferable(type: Movie.self) { result in
                        continuation.resume(with: result)
                    }
                }
                
                let thumbnail = await generateThumbnail(from: movie.url)
                let duration = await getVideoDuration(url: movie.url)
                
                pickedMedia.append(.video(url: movie.url, duration: duration, assetIdentifier: result.assetIdentifier))
            } catch {
                // Try to load as image
                do {
                    let imageData = try await withCheckedThrowingContinuation { continuation in
                        result.itemProvider.loadTransferable(type: Data.self) { result in
                            continuation.resume(with: result)
                        }
                    }
                    
                    if let uiImage = UIImage(data: imageData) {
                        let thumbnail = uiImage
                        let duration = Tokens.Timing.photoDefaultDuration
                        
                        pickedMedia.append(.photo(image: uiImage, assetIdentifier: result.assetIdentifier))
                    }
                } catch {
                    TapesLog.mediaPicker.error("Failed to load media item: \(error.localizedDescription)")
                }
            }
        }
        
        return pickedMedia
    }
    
    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 320)
        
        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            TapesLog.mediaPicker.error("Thumbnail generation failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func getVideoDuration(url: URL) async -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try? await asset.load(.duration)
        return CMTimeGetSeconds(duration ?? .zero)
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
        guard !isTitleFocused else { return }
        titleDraft = tape.title
        isTitleFocused = true
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleDraft = tape.title
            return
        }

        if trimmed != tape.title {
            let previousTape = tape
            tape.title = trimmed
            tape.updatedAt = Date()
            tapeStore.updateTape(tape, previousTape: previousTape)
        }

        titleDraft = tape.title
    }

    private func syncTitleDraftIfNeeded(force: Bool = false) {
        if force || !isTitleFocused {
            titleDraft = tape.title
        }
    }
}

#Preview("Dark Mode") {
    TapeCardView(
        tape: Binding.constant(Tape.sampleTapes[0]),
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
