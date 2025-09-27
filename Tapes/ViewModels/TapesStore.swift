import Foundation
import Photos
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation


// MARK: - TapesStore

@MainActor
public class TapesStore: ObservableObject {
    @Published public var tapes: [Tape] = []
    @Published public var selectedTape: Tape?
    @Published public var showingSettingsSheet = false
    
    public init() {
        // If persistence exists, load here; else leave current in-memory state
        
        // Always ensure at least one empty tape exists
        if tapes.isEmpty {
            let newReel = Tape(
                title: "New Reel",
                orientation: .portrait,
                scaleMode: .fit,
                transition: .none,
                transitionDuration: 0.5,
                clips: []
            )
            tapes.append(newReel)
        }
    }
    
    #if DEBUG
    func resetForDebug() {
        tapes = [Tape(
            title: "New Reel",
            orientation: .portrait,
            scaleMode: .fit,
            transition: .none,
            transitionDuration: 0.5,
            clips: []
        )]
        // Optionally clear temp imports dir here.
    }
    #endif
    
    // MARK: - Tape CRUD Operations
    
    public func createNewTape() -> Tape {
        let newTape = Tape()
        tapes.append(newTape)
        return newTape
    }
    
    public func getTape(by id: UUID) -> Tape? {
        return tapes.first { $0.id == id }
    }
    
    public func updateTape(_ tape: Tape) {
        if let index = tapes.firstIndex(where: { $0.id == tape.id }) {
            tapes[index] = tape
            
            // Update selected tape if it's the same tape
            if selectedTape?.id == tape.id {
                selectedTape = tape
            }
        }
    }
    
    public func deleteTape(_ tape: Tape) {
        tapes.removeAll { $0.id == tape.id }
    }
    
    public func deleteTape(by id: UUID) {
        tapes.removeAll { $0.id == id }
    }
    
    // MARK: - Selected Tape Management
    
    public func selectTape(_ tape: Tape) {
        selectedTape = tape
        showingSettingsSheet = true
    }
    
    public func selectTape(by id: UUID) {
        selectedTape = getTape(by: id)
    }
    
    public func clearSelectedTape() {
        selectedTape = nil
    }
    
    // MARK: - Clip Operations
    
    public func addClip(to tapeId: UUID, clip: Clip, at index: Int? = nil) {
        guard var tape = getTape(by: tapeId) else { return }
        tape.addClip(clip, at: index)
        updateTape(tape)
    }
    
    public func removeClip(from tapeId: UUID, at index: Int) {
        guard var tape = getTape(by: tapeId) else { return }
        tape.removeClip(at: index)
        updateTape(tape)
    }
    
    public func removeClip(from tapeId: UUID, clip: Clip) {
        guard var tape = getTape(by: tapeId) else { return }
        tape.removeClip(clip)
        updateTape(tape)
    }
    
    public func deleteClip(from tapeId: UUID, at index: Int) {
        guard var tape = getTape(by: tapeId) else { return }
        
        // Remove the clip at the specified index
        if index < tape.clips.count {
            tape.clips.remove(at: index)
        }
        
        // If this was the last clip, ensure we have an empty tape state
        if tape.clips.isEmpty {
            // Keep the tape but ensure it's in the correct empty state
            tape.clips = []
        }
        
        updateTape(tape)
    }
    
    public func deleteClip(from tapeId: UUID, clip: Clip) {
        guard var tape = getTape(by: tapeId) else { return }
        
        // Find and remove the specific clip
        tape.clips.removeAll { $0.id == clip.id }
        
        // If this was the last clip, ensure we have an empty tape state
        if tape.clips.isEmpty {
            // Keep the tape but ensure it's in the correct empty state
            tape.clips = []
        }
        
        updateTape(tape)
    }
    
    public func updateClip(in tapeId: UUID, clip: Clip) {
        guard var tape = getTape(by: tapeId) else { return }
        tape.updateClip(clip)
        updateTape(tape)
    }
    
    public func reorderClips(in tapeId: UUID, from source: IndexSet, to destination: Int) {
        guard var tape = getTape(by: tapeId) else { return }
        tape.reorderClips(from: source, to: destination)
        updateTape(tape)
    }
    
    // MARK: - Tape Settings Operations
    
    public func updateTapeSettings(
        for tapeId: UUID,
        title: String? = nil,
        orientation: TapeOrientation? = nil,
        scaleMode: ScaleMode? = nil,
        transition: TransitionType? = nil,
        transitionDuration: Double? = nil
    ) {
        guard var tape = getTape(by: tapeId) else { return }
        tape.updateSettings(
            title: title,
            orientation: orientation,
            scaleMode: scaleMode,
            transition: transition,
            transitionDuration: transitionDuration
        )
        updateTape(tape)
    }
    
    // MARK: - Convenience Methods
    
    public func getCurrentTape() -> Tape? {
        return tapes.first
    }
    
    public func getTapeCount() -> Int {
        return tapes.count
    }
    
    public func isEmpty() -> Bool {
        return tapes.isEmpty
    }
    
    // MARK: - Bulk Operations
    
    public func clearAllTapes() {
        tapes.removeAll()
    }
    
    public func duplicateTape(_ tape: Tape) -> Tape {
        var duplicatedTape = tape
        duplicatedTape.id = UUID()
        duplicatedTape.title = "\(tape.title) Copy"
        duplicatedTape.createdAt = Date()
        duplicatedTape.updatedAt = Date()
        
        // Duplicate clips with new IDs
        duplicatedTape.clips = tape.clips.map { clip in
            var newClip = clip
            newClip.id = UUID()
            newClip.createdAt = Date()
            newClip.updatedAt = Date()
            return newClip
        }
        
        tapes.append(duplicatedTape)
        return duplicatedTape
    }
    
    // MARK: - Search and Filter
    
    public func searchTapes(query: String) -> [Tape] {
        guard !query.isEmpty else { return tapes }
        return tapes.filter { tape in
            tape.title.localizedCaseInsensitiveContains(query)
        }
    }
    
    public func getTapesSortedByDate(ascending: Bool = false) -> [Tape] {
        return tapes.sorted { tape1, tape2 in
            ascending ? 
                tape1.updatedAt < tape2.updatedAt : 
                tape1.updatedAt > tape2.updatedAt
        }
    }
    
    public func getTapesSortedByTitle(ascending: Bool = true) -> [Tape] {
        return tapes.sorted { tape1, tape2 in
            ascending ? 
                tape1.title < tape2.title : 
                tape1.title > tape2.title
        }
    }
}

// MARK: - TapesStore Extensions

extension TapesStore {
    /// Creates a new tape with specific settings
    public func createTape(
        title: String = "New Tape",
        orientation: TapeOrientation = .portrait,
        scaleMode: ScaleMode = .fit,
        transition: TransitionType = .none,
        transitionDuration: Double = 0.5
    ) -> Tape {
        let newTape = Tape(
            title: title,
            orientation: orientation,
            scaleMode: scaleMode,
            transition: transition,
            transitionDuration: transitionDuration
        )
        tapes.append(newTape)
        return newTape
    }
    
    /// Adds a clip from PHAsset to a tape
    public func addClipFromAsset(
        to tapeId: UUID,
        asset: PHAsset,
        at index: Int? = nil,
        rotateQuarterTurns: Int = 0,
        overrideScaleMode: ScaleMode? = nil
    ) {
        let clip = Clip.from(
            asset: asset,
            rotateQuarterTurns: rotateQuarterTurns,
            overrideScaleMode: overrideScaleMode
        )
        addClip(to: tapeId, clip: clip, at: index)
    }
    
    /// Gets all clips from a tape
    public func getClips(from tapeId: UUID) -> [Clip] {
        return getTape(by: tapeId)?.clips ?? []
    }
    
    /// Gets clip count for a tape
    public func getClipCount(for tapeId: UUID) -> Int {
        return getTape(by: tapeId)?.clipCount ?? 0
    }
    
    /// Inserts a clip at the center boundary of the carousel
    public func insertClip(_ clip: Clip, in tapeId: UUID, atCenterOfCarouselIndex index: Int) {
        guard var tape = getTape(by: tapeId) else { return }
        
        // Insert at the specified center index
        let insertIndex = min(index, tape.clips.count)
        tape.addClip(clip, at: insertIndex)
        updateTape(tape)
        
        // Provide haptic feedback
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
    
    /// Formats duration in seconds to mm:ss format
    public func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Gets the current center index for a tape (for carousel snapping)
    public func getCenterIndex(for tapeId: UUID) -> Int {
        guard let tape = getTape(by: tapeId) else { return 0 }
        // For empty tape, center index is 0
        // For non-empty tape, center index is the middle of clips
        return tape.clips.isEmpty ? 0 : tape.clips.count / 2
    }
    
    /// Inserts a clip at a specific placeholder position
    public func insertClipAtPlaceholder(_ clip: Clip, in tapeId: UUID, placeholder: CarouselItem) {
        guard var tape = getTape(by: tapeId) else { return }
        
        let insertIndex: Int
        switch placeholder {
        case .startPlus:
            insertIndex = 0
        case .endPlus:
            insertIndex = tape.clips.count
        case .clip:
            // This shouldn't happen, but fallback to center
            insertIndex = tape.clips.count / 2
        }
        
        tape.addClip(clip, at: insertIndex)
        updateTape(tape)
        
        // Provide haptic feedback
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
    
    /// Inserts multiple media items in order
    public func insertMedia(_ items: [PickedMedia], at strategy: InsertionStrategy, in tapeID: UUID) {
        guard var tape = getTape(by: tapeID) else { return }
        
        let startIndex: Int
        switch strategy {
        case .replaceThenAppend(let index):
            startIndex = index
        case .insertAtCenter:
            startIndex = getCenterIndex(for: tapeID)
        }
        
        // Convert picked media to clips
        var newClips: [Clip] = []
        for item in items {
            let clip: Clip
            switch item {
            case .video(let url):
                clip = Clip.fromVideo(url: url, duration: 0.0, thumbnail: nil)
            case .photo(let image):
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    clip = Clip.fromImage(imageData: imageData, duration: Tokens.Timing.photoDefaultDuration, thumbnail: image)
                } else {
                    continue // Skip invalid image
                }
            }
            newClips.append(clip)
        }
        
        // Insert clips in order
        for (offset, clip) in newClips.enumerated() {
            let insertAt = startIndex + offset
            tape.addClip(clip, at: min(insertAt, tape.clips.count))
        }
        
        updateTape(tape)
        
        // Provide haptic feedback
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
    
    /// Inserts picked media at the center of a tape (single source of truth)
    @MainActor
    public func insertAtCenter(tapeID: Tape.ID, picked: [PickedMedia]) {
        guard let tIndex = tapes.firstIndex(where: { $0.id == tapeID }) else {
            print("❌ TapeStore.insertAtCenter: tape not found \(tapeID)")
            return
        }

        // Convert PickedMediaItem -> Clip using our existing factories
        var newClips: [Clip] = []
        for m in picked {
            switch m {
            case .video(let url):
                // For now, create clip with default values - async processing can be added later
                let clip = Clip.fromVideo(url: url, duration: 0.0, thumbnail: nil)
                newClips.append(clip)
            case .photo(let image):
                // Convert image to data and use default duration
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    let clip = Clip.fromImage(imageData: imageData, duration: Tokens.Timing.photoDefaultDuration, thumbnail: image)
                    newClips.append(clip)
                } else {
                    print("⚠️ Could not build Clip from photo (UIImage)")
                }
            }
        }
        
        guard !newClips.isEmpty else {
            print("⚠️ insertAtCenter: nothing to insert")
            return
        }

        // Decide insertion index (center if we track it; else append)
        let currentCount = tapes[tIndex].clips.count
        let insertionIndex = currentCount // For now, append at the end
        
        // Create a new tape with updated clips to trigger @Published
        var updatedTape = tapes[tIndex]
        updatedTape.clips.insert(contentsOf: newClips, at: min(insertionIndex, updatedTape.clips.count))
        tapes[tIndex] = updatedTape

        print("✅ Inserted \(newClips.count) clip(s) at index \(insertionIndex) in tape \"\(tapes[tIndex].title)\"")
        
        // Generate thumbnails and duration for video clips asynchronously
        for clip in newClips {
            if clip.clipType == .video, let url = clip.localURL {
                generateThumbAndDuration(for: url, clipID: clip.id, tapeID: tapeID)
            }
        }
    }
    
    /// Insert at the visual "center" of the carousel for a specific tape binding.
    @MainActor
    func insertAtCenter(into tape: Binding<Tape>, picked: [PickedMedia]) {
        guard !picked.isEmpty else { return }
        
        // compute insert index from your existing "center" rule; for now append:
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
        
        // insert at calculated index; simple append example:
        var updatedTape = tape.wrappedValue
        print("🔍 Before insert: tape has \(updatedTape.clips.count) clips")
        updatedTape.clips.append(contentsOf: newClips)
        print("🔍 After insert: tape has \(updatedTape.clips.count) clips")
        tape.wrappedValue = updatedTape
        objectWillChange.send()
        print("✅ Inserted \(newClips.count) clips into tape \(tape.wrappedValue.id)")
    }
    
    /// Update a specific clip in a tape with proper publishing
    @MainActor
    func updateClip(_ id: UUID, transform: (inout Clip) -> Void, in tapeID: UUID) {
        guard let t = tapes.firstIndex(where: { $0.id == tapeID }) else { 
            print("❌ TapeStore.updateClip: tape not found \(tapeID)")
            return 
        }
        guard let c = tapes[t].clips.firstIndex(where: { $0.id == id }) else { 
            print("❌ TapeStore.updateClip: clip not found \(id)")
            return 
        }
        
        var newTape = tapes[t]
        transform(&newTape.clips[c])          // mutate copy
        tapes[t] = newTape                    // REASSIGN to publish
        print("✅ Updated clip \(id) in tape \(tapeID)")
    }
    
    /// Generate thumbnail from video URL
    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 320)
        
        do {
            let cgImage = try await imageGenerator.image(at: CMTime.zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    /// Generate thumbnail and duration for a clip using robust async methods
    func generateThumbAndDuration(for url: URL, clipID: UUID, tapeID: UUID) {
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            do {
                // Async duration (iOS 16+)
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.updateClip(clipID, transform: { $0.duration = duration.seconds }, in: tapeID)
                }

                // Async CGImage
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)

                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                    guard let cg else { return }
                    let ui = UIImage(cgImage: cg)
                    Task { @MainActor in
                        self.updateClip(clipID, transform: { $0.thumbnail = ui.jpegData(compressionQuality: 0.8) }, in: tapeID)
                    }
                }
            } catch {
                print("⚠️ Thumb/duration load failed:", error.localizedDescription)
            }
        }
    }
}
