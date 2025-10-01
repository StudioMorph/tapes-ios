import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum ImportSource {
    case leftPlaceholder(index: Int)
    case rightPlaceholder(index: Int)
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
    
    // Carousel position tracking - all in clip-space
    @State private var savedCarouselPosition: Int = 0 // Clip-space position (0 = start, N = end)
    @State private var pendingAdvancement: Int = 0 // How many positions to advance after insertion (clip-space)
    
    // Session flag for initial positioning
    @State private var isNewSession = true
    
    // Pending target for programmatic scroll (scoped by tape ID)
    @State private var pendingTargetItemIndex: Int? = nil
    
    // Initial carousel position - set to last position in clip-space
    private var initialCarouselPosition: Int {
        return tape.clips.count // Clip-space: 0 = start, N = end
    }
    
    var body: some View {
        let _ = print("🎯 TapeCardView: tape id=\(tape.id), clips=\(tape.clips.count)")
        VStack(alignment: .leading, spacing: 0) {
            // Title row
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Left group: Title (hug) + 4 + pencil
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(tape.title)
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                    
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            let thumbW = floor((screenW - Tokens.FAB.size) / 2.0)
            let thumbH = floor(thumbW * 9.0 / 16.0)
            
            
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
                    onPlaceholderTap: { item in
                        // Store import source and show picker
                        switch item {
                        case .startPlus:
                            importSource = .leftPlaceholder(index: 0)
                        case .endPlus:
                            importSource = .rightPlaceholder(index: tape.clips.count)
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
                        
                        print("🎯 calc: p_snapshot=\(pSnapshot), k=\(k), tape=\(tape.id)")
                        
                        // Always use the working insertAtCenter method, but adjust positioning
                        switch importSource {
                        case .leftPlaceholder(let index):
                            // Insert at start by temporarily modifying the tape
                            let originalClips = tape.clips
                            tape.clips = []
                            tapeStore.insertAtCenter(into: $tape, picked: picked)
                            // Move clips to start
                            let newClips = tape.clips
                            tape.clips = newClips + originalClips
                            print("🎯 Left placeholder: moved \(newClips.count) clips to start")
                        case .rightPlaceholder(let index):
                            // Insert at end by using insertAtCenter and then moving to end
                            print("🎯 Right placeholder: appending \(picked.count) items to end")
                            let originalClips = tape.clips
                            tapeStore.insertAtCenter(into: $tape, picked: picked)
                            let allClips = tape.clips
                            // Extract only the new clips (the ones added by insertAtCenter)
                            let newClips = Array(allClips.suffix(picked.count))
                            // Move new clips to end
                            tape.clips = originalClips + newClips
                            print("🎯 Right placeholder: added \(picked.count) clips to end, total clips: \(tape.clips.count)")
                        case .centerFAB:
                            // Insert at current carousel position (where FAB is positioned)
                            let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                            insertClipsAtPosition(picked: picked, at: insertionIndex, into: $tape)
                            print("🎯 Center FAB: inserted at position \(insertionIndex) (carousel position: \(savedCarouselPosition))")
                        case .none:
                            // Fallback to center
                            tapeStore.insertAtCenter(into: $tape, picked: picked)
                            print("🎯 None: fallback to center")
                        }
                        
                        // Calculate target position in clip-space after insertion
                        let pAfter = pSnapshot + k
                        let targetItemIndex = pAfter + 1 // Convert to item-space (+1 for start-plus)
                        
                        print("🎯 calc: p_after=\(pAfter), targetItemIndex=\(targetItemIndex), tape=\(tape.id)")
                        
                        // Set pending target for programmatic scroll (scoped by tape ID)
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
                
                print("🎯 calc: p_snapshot=\(pSnapshot), k=\(k), tape=\(tape.id)")
                
                // Insert media based on source
                switch source {
                case .centerFAB:
                    // Insert at current carousel position (where FAB is positioned)
                    let insertionIndex = calculateInsertionIndex(from: savedCarouselPosition, tape: tape)
                    insertClipsAtPosition(picked: picked, at: insertionIndex, into: $tape)
                    print("🎯 Camera FAB: inserted at position \(insertionIndex) (carousel position: \(savedCarouselPosition))")
                default:
                    // Fallback to center
                    tapeStore.insertAtCenter(into: $tape, picked: picked)
                    print("🎯 Camera: fallback to center")
                }
                
                // Calculate target position in clip-space after insertion
                let pAfter = pSnapshot + k
                let targetItemIndex = pAfter + 1 // Convert to item-space (+1 for start-plus)
                
                print("🎯 calc: p_after=\(pAfter), targetItemIndex=\(targetItemIndex), tape=\(tape.id)")
                
                // Set pending target for programmatic scroll (scoped by tape ID)
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
    
    /// Insert clips at a specific position in the tape
    private func insertClipsAtPosition(picked: [PickedMedia], at index: Int, into tape: Binding<Tape>) {
        guard !picked.isEmpty else { return }
        
        // Convert picked media to clips
        var newClips: [Clip] = []
        for item in picked {
            switch item {
            case .video(let url):
                let clip = Clip.fromVideo(url: url, duration: 0.0, thumbnail: nil)
                newClips.append(clip)
            case .photo(let image):
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    let clip = Clip.fromImage(imageData: imageData, duration: Tokens.Timing.photoDefaultDuration, thumbnail: image)
                    newClips.append(clip)
                }
            }
        }
        
        // Insert clips at the calculated position
        var updatedTape = tape.wrappedValue
        let insertIndex = min(index, updatedTape.clips.count)
        updatedTape.clips.insert(contentsOf: newClips, at: insertIndex)
        tape.wrappedValue = updatedTape
        
        print("✅ Inserted \(newClips.count) clips at index \(insertIndex) in tape \(updatedTape.id)")
        
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
                
                pickedMedia.append(.video(movie.url))
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
                        
                        pickedMedia.append(.photo(uiImage))
                    }
                } catch {
                    print("Error loading media item: \(error)")
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
            print("Error generating thumbnail: \(error)")
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
            
            print("🧩 first-content: tape=\(tape.id) now has clips > 0 → flag=true; inserting new empty at top")
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