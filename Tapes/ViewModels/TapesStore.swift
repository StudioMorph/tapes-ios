import Foundation
import Photos
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation


// MARK: - Clip Loading State Models

public enum ClipLoadingPhase: Equatable {
    case queued
    case transferring
    case processing
    case ready
    case error(message: String)
    
    var isTerminal: Bool {
        switch self {
        case .ready, .error:
            return true
        default:
            return false
        }
    }
}

public extension ClipLoadingPhase {
    static func == (lhs: ClipLoadingPhase, rhs: ClipLoadingPhase) -> Bool {
        switch (lhs, rhs) {
        case (.queued, .queued),
             (.transferring, .transferring),
             (.processing, .processing),
             (.ready, .ready):
            return true
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}

public struct ClipLoadingState: Equatable {
    public let phase: ClipLoadingPhase
    public let progress: Double?
    public let updatedAt: Date
    
    public init(phase: ClipLoadingPhase, progress: Double? = nil, updatedAt: Date = Date()) {
        self.phase = phase
        self.progress = progress
        self.updatedAt = updatedAt
    }
    
    public func updating(phase: ClipLoadingPhase, progress: Double? = nil) -> ClipLoadingState {
        ClipLoadingState(phase: phase, progress: progress, updatedAt: Date())
    }
}

public struct ClipBatchProgress: Equatable {
    public let total: Int
    public let ready: Int
    public let failed: Int
    
    public var inProgress: Int {
        total - ready - failed
    }
    
    public var fractionComplete: Double {
        guard total > 0 else { return 1.0 }
        return Double(ready) / Double(total)
    }
}

// MARK: - TapesStore

@MainActor
public class TapesStore: ObservableObject {
    @Published public var tapes: [Tape] = []
    @Published public var selectedTape: Tape?
    @Published public var showingSettingsSheet = false
    @Published public var latestInsertedTapeID: UUID?
    @Published public var pendingTapeRevealID: UUID?
    @Published public var albumAssociationError: String?
    @Published public private(set) var clipLoadingStates: [UUID: ClipLoadingState] = [:]
    
    private struct AlbumAssociationQueueEntry {
        let id: UUID
        let task: Task<Void, Never>
    }
    
    private struct ClipResolutionTimeoutError: Error {}

    private static let clipResolutionTimeout: TimeInterval = 30
    
    private let albumService: TapeAlbumServicing
    private var placeholderTapeMap: [UUID: UUID] = [:]
    private var albumAssociationQueues: [UUID: AlbumAssociationQueueEntry] = [:]
    
    // MARK: - Persistence
    private let persistenceKey = "SavedTapes"
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var persistenceURL: URL {
        documentsDirectory.appendingPathComponent("tapes.json")
    }
    
    public init(albumService: TapeAlbumServicing = TapeAlbumService()) {
        self.albumService = albumService
        loadTapesFromDisk()
        
        // Always ensure at least one empty tape exists
        if tapes.isEmpty {
            let newReel = Tape(
                title: "New Reel",
                orientation: .portrait,
                scaleMode: .fit,
                transition: .none,
                transitionDuration: 0.5,
                clips: [],
                hasReceivedFirstContent: false
            )
            tapes.append(newReel)
            saveTapesToDisk()
        }
        
        // Restore empty tape invariant after loading
        restoreEmptyTapeInvariant()
        restoreMissingClipMetadata()
        scheduleLegacyAlbumAssociation()
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
        autoSave()
        return newTape
    }
    
    public func getTape(by id: UUID) -> Tape? {
        return tapes.first { $0.id == id }
    }
    
    public func updateTape(_ tape: Tape, previousTape explicitPreviousTape: Tape? = nil) {
        if let index = tapes.firstIndex(where: { $0.id == tape.id }) {
            let previousTape = explicitPreviousTape ?? tapes[index]
            tapes[index] = tape
            
            // Update selected tape if it's the same tape
            if selectedTape?.id == tape.id {
                selectedTape = tape
            }
            
            // Auto-save changes
            autoSave()
            handleAlbumRenameIfNeeded(previousTape: previousTape, updatedTape: tape)
        }
    }
    
    public func deleteTape(_ tape: Tape) {
        scheduleAlbumDeletionIfNeeded(for: tape)
        tapes.removeAll { $0.id == tape.id }
        autoSave()
    }

    public func deleteTape(by id: UUID) {
        if let tape = getTape(by: id) {
            scheduleAlbumDeletionIfNeeded(for: tape)
        }
        tapes.removeAll { $0.id == id }
        autoSave()
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
        guard index >= 0 && index < tape.clips.count else { return }
        let clip = tape.clips[index]
        if clip.isPlaceholder {
            purgePlaceholderTrackingIfNeeded(for: clip.id)
        }
        tape.removeClip(at: index)
        updateTape(tape)
    }
    
    public func removeClip(from tapeId: UUID, clip: Clip) {
        guard var tape = getTape(by: tapeId) else { return }
        if clip.isPlaceholder {
            purgePlaceholderTrackingIfNeeded(for: clip.id)
        }
        tape.removeClip(clip)
        updateTape(tape)
    }
    
    public func deleteClip(from tapeId: UUID, at index: Int) {
        guard var tape = getTape(by: tapeId) else { return }
        
        // Remove the clip at the specified index
        if index < tape.clips.count {
            let clip = tape.clips[index]
            if clip.isPlaceholder {
                purgePlaceholderTrackingIfNeeded(for: clip.id)
            }
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
        if clip.isPlaceholder {
            purgePlaceholderTrackingIfNeeded(for: clip.id)
        }
        
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
    
    @MainActor
    public func associateClipsWithAlbum(tapeID: UUID, clips: [Clip]) {
        let assetIdentifiers = clips.compactMap { $0.assetLocalId }.filter { !$0.isEmpty }
        guard !assetIdentifiers.isEmpty else { return }
        guard let tape = getTape(by: tapeID) else { return }
        let tapeSnapshot = tape
        let previousTask = albumAssociationQueues[tapeID]?.task
        let entryID = UUID()
        let newTask = Task.detached(priority: .utility) { [weak self] in
            if let previousTask {
                _ = await previousTask.value
            }
            guard let self else { return }
            await self.processAlbumAssociation(
                tapeID: tapeID,
                tape: tapeSnapshot,
                assetIdentifiers: assetIdentifiers
            )
            await MainActor.run {
                if self.albumAssociationQueues[tapeID]?.id == entryID {
                    self.albumAssociationQueues.removeValue(forKey: tapeID)
                }
            }
        }
        albumAssociationQueues[tapeID] = AlbumAssociationQueueEntry(id: entryID, task: newTask)
    }

    // MARK: - Placeholder & Import Handling

    @MainActor
    @discardableResult
    public func insertPlaceholderClips(count: Int, into tapeID: UUID, at insertionIndex: Int) -> [UUID] {
        guard count > 0, let tapeIndex = tapes.firstIndex(where: { $0.id == tapeID }) else {
            return []
        }
        var tape = tapes[tapeIndex]
        var placeholderIDs: [UUID] = []
        for offset in 0..<count {
            var placeholder = Clip.placeholder()
            let targetIndex = min(insertionIndex + offset, tape.clips.count)
            tape.clips.insert(placeholder, at: targetIndex)
            placeholderIDs.append(placeholder.id)
            placeholderTapeMap[placeholder.id] = tapeID
            clipLoadingStates[placeholder.id] = ClipLoadingState(phase: .queued)
        }
        tapes[tapeIndex] = tape
        autoSave()
        return placeholderIDs
    }

    public func processPickerResults(
        _ results: [PHPickerResult],
        placeholderIDs: [UUID],
        tapeID: UUID
    ) {
        guard !results.isEmpty, results.count == placeholderIDs.count else { return }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            for (placeholderID, result) in zip(placeholderIDs, results) {
                await self.setClipLoadingState(placeholderID, phase: .transferring)
                do {
                    let media = try await self.resolvePickedMediaWithTimeout(
                        result,
                        timeout: Self.clipResolutionTimeout
                    )
                    await self.setClipLoadingState(placeholderID, phase: .processing)
                    await self.applyResolvedMedia(media, to: placeholderID, tapeID: tapeID)
                } catch {
                    let message: String
                    if error is ClipResolutionTimeoutError {
                        message = "Timed out"
                    } else {
                        message = error.localizedDescription
                    }
                    await self.markPlaceholderFailure(
                        placeholderID: placeholderID,
                        tapeID: tapeID,
                        error: message
                    )
                }
            }
        }
    }

    @MainActor
    public func batchProgress(for tapeID: UUID) -> ClipBatchProgress? {
        let activeIDs = placeholderTapeMap.filter { $0.value == tapeID }.map(\.key)
        guard !activeIDs.isEmpty else { return nil }
        var total = 0
        var ready = 0
        var failed = 0
        for clipID in activeIDs {
            guard let state = clipLoadingStates[clipID] else { continue }
            total += 1
            switch state.phase {
            case .ready:
                ready += 1
            case .error:
                failed += 1
            default:
                break
            }
        }
        guard total > 0 else { return nil }
        return ClipBatchProgress(total: total, ready: ready, failed: failed)
    }

    @MainActor
    private func setClipLoadingState(_ clipID: UUID, phase: ClipLoadingPhase, progress: Double? = nil) {
        let existing = clipLoadingStates[clipID]
        let newState = existing?.updating(phase: phase, progress: progress) ?? ClipLoadingState(phase: phase, progress: progress)
        clipLoadingStates[clipID] = newState
        if phase == .ready, let tapeID = placeholderTapeMap[clipID] {
            evaluateBatchCompletion(for: tapeID)
        }
    }

    @MainActor
    private func applyResolvedMedia(_ media: PickedMedia, to placeholderID: UUID, tapeID: UUID) async {
        guard let tapeIndex = tapes.firstIndex(where: { $0.id == tapeID }) else { return }
        var tape = tapes[tapeIndex]
        guard let clipIndex = tape.clips.firstIndex(where: { $0.id == placeholderID }) else { return }

        guard var resolvedClip = buildClip(from: media) else {
            await markPlaceholderFailure(placeholderID: placeholderID, tapeID: tapeID, error: "Unsupported media.")
            return
        }

        resolvedClip.id = placeholderID
        resolvedClip.isPlaceholder = false
        resolvedClip.createdAt = Date()
        resolvedClip.updatedAt = Date()
        tape.clips[clipIndex] = resolvedClip
        tapes[tapeIndex] = tape
        setClipLoadingState(placeholderID, phase: .ready)
        autoSave()
        associateClipsWithAlbum(tapeID: tapeID, clips: [resolvedClip])

        switch media {
        case let .video(url, _, _):
            generateThumbAndDuration(for: url, clipID: resolvedClip.id, tapeID: tapeID)
        case .photo:
            break
        }
    }

    @MainActor
    private func markPlaceholderFailure(placeholderID: UUID, tapeID: UUID, error: String) {
        TapesLog.store.warning("Import placeholder \(placeholderID) failed for tape \(tapeID): \(error)")
        removePlaceholderClip(placeholderID, from: tapeID)
    }

private func evaluateBatchCompletion(for tapeID: UUID) {
    let ids = placeholderTapeMap.compactMap { $0.value == tapeID ? $0.key : nil }
    guard !ids.isEmpty else { return }
    let allReady = ids.allSatisfy { clipLoadingStates[$0]?.phase == .ready }
    if allReady {
        for id in ids {
            clipLoadingStates.removeValue(forKey: id)
            placeholderTapeMap.removeValue(forKey: id)
        }
    }
    }

    private func buildClip(from media: PickedMedia) -> Clip? {
        switch media {
        case let .video(url, duration, assetIdentifier):
            var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
            if clip.duration <= 0 {
                let asset = AVURLAsset(url: url)
                let seconds = CMTimeGetSeconds(asset.duration)
                clip.duration = seconds > 0 ? seconds : 0
            }
            return clip
        case let .photo(image, assetIdentifier):
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            return Clip.fromImage(
                imageData: data,
                duration: Tokens.Timing.photoDefaultDuration,
                thumbnail: image,
                assetLocalId: assetIdentifier
            )
        }
    }

    private func resolvePickedMediaWithTimeout(_ result: PHPickerResult, timeout: TimeInterval) async throws -> PickedMedia {
        try await withThrowingTaskGroup(of: PickedMedia.self) { group in
            group.addTask {
                try await resolvePickedMedia(from: result)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ClipResolutionTimeoutError()
            }
            guard let value = try await group.next() else {
                group.cancelAll()
                throw ClipResolutionTimeoutError()
            }
            group.cancelAll()
            return value
        }
    }

    @MainActor
    private func removePlaceholderClip(_ placeholderID: UUID, from tapeID: UUID) {
        clipLoadingStates.removeValue(forKey: placeholderID)
        placeholderTapeMap.removeValue(forKey: placeholderID)
        if let tapeIndex = tapes.firstIndex(where: { $0.id == tapeID }) {
            var tape = tapes[tapeIndex]
            if let clipIndex = tape.clips.firstIndex(where: { $0.id == placeholderID }) {
                tape.clips.remove(at: clipIndex)
                tapes[tapeIndex] = tape
                autoSave()
            }
        }
        evaluateBatchCompletion(for: tapeID)
    }

    private func purgePlaceholderTrackingIfNeeded(for clipID: UUID) {
        clipLoadingStates.removeValue(forKey: clipID)
        if let tapeID = placeholderTapeMap.removeValue(forKey: clipID) {
            evaluateBatchCompletion(for: tapeID)
        }
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
        insertEmptyTapeAtTop()
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
        autoSave()
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
        associateClipsWithAlbum(tapeID: tapeId, clips: [clip])
        
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
    public func renameTapeTitle(_ tapeID: UUID, to newTitle: String) {
        guard var tape = getTape(by: tapeID) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previousTape = tape
        if trimmed != tape.title {
            tape.title = trimmed
            tape.updatedAt = Date()
            updateTape(tape, previousTape: previousTape)
        }
    }

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
        associateClipsWithAlbum(tapeID: tapeId, clips: [clip])
        
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
            case let .video(url, duration, assetIdentifier):
                var videoClip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
                if videoClip.duration <= 0 {
                    let asset = AVURLAsset(url: url)
                    let seconds = CMTimeGetSeconds(asset.duration)
                    if seconds > 0 {
                        videoClip.duration = seconds
                    }
                }
                clip = videoClip
            case let .photo(image, assetIdentifier):
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    clip = Clip.fromImage(
                        imageData: imageData,
                        duration: Tokens.Timing.photoDefaultDuration,
                        thumbnail: image,
                        assetLocalId: assetIdentifier
                    )
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
        associateClipsWithAlbum(tapeID: tapeID, clips: newClips)
        
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
            TapesLog.store.error("insertAtCenter: tape not found \(tapeID)")
            return
        }

        // Convert PickedMediaItem -> Clip using our existing factories
        var newClips: [Clip] = []
        for m in picked {
            switch m {
            case let .video(url, duration, assetIdentifier):
                var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
                if clip.duration <= 0 {
                    let asset = AVURLAsset(url: url)
                    let seconds = CMTimeGetSeconds(asset.duration)
                    if seconds > 0 {
                        clip.duration = seconds
                    }
                }
                newClips.append(clip)
            case let .photo(image, assetIdentifier):
                // Convert image to data and use default duration
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    let clip = Clip.fromImage(
                        imageData: imageData,
                        duration: Tokens.Timing.photoDefaultDuration,
                        thumbnail: image,
                        assetLocalId: assetIdentifier
                    )
                    newClips.append(clip)
                } else {
                    TapesLog.store.warning("Could not build clip from UIImage data")
                }
            }
        }
        
        guard !newClips.isEmpty else {
            TapesLog.store.warning("insertAtCenter called with no clips to insert")
            return
        }

        // Decide insertion index (center if we track it; else append)
        let currentCount = tapes[tIndex].clips.count
        let insertionIndex = currentCount // For now, append at the end
        
        // Create a new tape with updated clips to trigger @Published
        var updatedTape = tapes[tIndex]
        updatedTape.clips.insert(contentsOf: newClips, at: min(insertionIndex, updatedTape.clips.count))
        tapes[tIndex] = updatedTape

        // Auto-save changes
        autoSave()
        associateClipsWithAlbum(tapeID: tapeID, clips: newClips)
        
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
        
        var newClips: [Clip] = []
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
                newClips.append(clip)
            case let .photo(image, assetIdentifier):
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    let clip = Clip.fromImage(
                        imageData: imageData,
                        duration: Tokens.Timing.photoDefaultDuration,
                        thumbnail: image,
                        assetLocalId: assetIdentifier
                    )
                    newClips.append(clip)
                }
            }
        }
        
        guard !newClips.isEmpty else { return }
        
        var updatedTape = tape.wrappedValue
        updatedTape.clips.append(contentsOf: newClips)
        tape.wrappedValue = updatedTape
        objectWillChange.send()
        
        autoSave()
        associateClipsWithAlbum(tapeID: tape.wrappedValue.id, clips: newClips)
        
        for clip in newClips {
            if clip.clipType == .video, let url = clip.localURL {
                generateThumbAndDuration(for: url, clipID: clip.id, tapeID: tape.wrappedValue.id)
            }
        }
    }
    
    /// Insert clips at an explicit index (struct-safe publish)
    @MainActor
    func insert(_ newClips: [Clip], into tapeID: UUID, at index: Int) {
        guard let ti = tapes.firstIndex(where: { $0.id == tapeID }) else { return }
        var tape = tapes[ti]
        let at = max(0, min(index, tape.clips.count))
        tape.clips.insert(contentsOf: newClips, at: at)
        tapes[ti] = tape // reassign to publish
        
        autoSave()
        
        for clip in newClips {
            if clip.clipType == .video, let url = clip.localURL {
                generateThumbAndDuration(for: url, clipID: clip.id, tapeID: tapeID)
            }
        }
    }
    
    /// Update a specific clip in a tape with proper publishing
    @MainActor
    func updateClip(_ id: UUID, transform: (inout Clip) -> Void, in tapeID: UUID) {
        guard let t = tapes.firstIndex(where: { $0.id == tapeID }) else { 
            TapesLog.store.error("updateClip: tape not found \(tapeID)")
            return 
        }
        guard let c = tapes[t].clips.firstIndex(where: { $0.id == id }) else { 
            TapesLog.store.error("updateClip: clip not found \(id)")
            return 
        }
        
        var newTape = tapes[t]
        transform(&newTape.clips[c])          // mutate copy
        tapes[t] = newTape                    // REASSIGN to publish
                        
        // Auto-save changes
        autoSave()
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
            TapesLog.store.error("Failed to generate thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Generate thumbnail and duration for a clip using robust async methods
    func generateThumbAndDuration(for url: URL, clipID: UUID, tapeID: UUID) {
        let asset = AVURLAsset(url: url)
        processAssetMetadata(asset, clipID: clipID, tapeID: tapeID)
    }

    private func processAssetMetadata(_ asset: AVAsset, clipID: UUID, tapeID: UUID) {
        Task.detached(priority: .utility) {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.updateClip(clipID, transform: { $0.duration = duration.seconds }, in: tapeID)
                }

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
                TapesLog.store.error("Failed to load thumbnail/duration: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Persistence Methods
    
    /// Save tapes to disk
    private func saveTapesToDisk() {
        do {
            let sanitized = tapes.map { $0.removingPlaceholders() }
            let data = try JSONEncoder().encode(sanitized)
            try data.write(to: persistenceURL)
        } catch {
            TapesLog.store.error("Failed to save tapes: \(error.localizedDescription)")
        }
    }
    
    /// Load tapes from disk
    private func loadTapesFromDisk() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            tapes = try JSONDecoder().decode([Tape].self, from: data)
        } catch {
            TapesLog.store.warning("No saved tapes found or failed to load: \(error.localizedDescription)")
            tapes = []
        }
    }
    
    /// Auto-save when tapes change
    private func autoSave() {
        saveTapesToDisk()
    }
    
    // MARK: - Empty Tape Management
    
    /// Insert a new empty tape at index 0
    public func insertEmptyTapeAtTop() {
        let newEmptyTape = Tape(
            title: "New Reel",
            orientation: .portrait,
            scaleMode: .fit,
            transition: .none,
            transitionDuration: 0.5,
            clips: [],
            hasReceivedFirstContent: false
        )
        withAnimation(Animation.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.12)) {
            tapes.insert(newEmptyTape, at: 0)
        }
        pendingTapeRevealID = newEmptyTape.id
        latestInsertedTapeID = nil
        let revealDelay = 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) { [weak self] in
            guard let self else { return }
            withAnimation {
                self.latestInsertedTapeID = newEmptyTape.id
                self.pendingTapeRevealID = nil
            }
        }
        autoSave()
    }

    public func clearLatestInsertedTapeID(_ identifier: UUID) {
        if latestInsertedTapeID == identifier {
            latestInsertedTapeID = nil
        }
    }
    
    /// Restore any missing metadata on clips (durations/thumbnails) after loading from disk
    private func restoreMissingClipMetadata() {
        var didMutate = false

        for tIndex in tapes.indices {
            var tape = tapes[tIndex]
            var mutatedTape = false

            for cIndex in tape.clips.indices {
                var clip = tape.clips[cIndex]

                if clip.clipType == .image && clip.duration <= 0 {
                    clip.duration = Tokens.Timing.photoDefaultDuration
                    clip.updatedAt = Date()
                    mutatedTape = true
                }

                if clip.clipType == .video && clip.duration <= 0 {
                    if let url = clip.localURL {
                        generateThumbAndDuration(for: url, clipID: clip.id, tapeID: tape.id)
                    } else if let assetId = clip.assetLocalId {
                        regenerateMetadataFromPhotoLibrary(assetLocalId: assetId, clipID: clip.id, tapeID: tape.id)
                    }
                }

                tape.clips[cIndex] = clip
            }

            if mutatedTape {
                tapes[tIndex] = tape
                didMutate = true
            }
        }

        if didMutate {
            autoSave()
        }
    }

    @MainActor
    private func scheduleLegacyAlbumAssociation() {
        for tape in tapes where !tape.clips.isEmpty && !tape.hasAssociatedAlbum {
            associateClipsWithAlbum(tapeID: tape.id, clips: tape.clips)
        }
    }

    /// Attempt to recover duration/thumbnail for videos that only have a Photos asset identifier
    private func regenerateMetadataFromPhotoLibrary(assetLocalId: String, clipID: UUID, tapeID: UUID) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let asset = fetch.firstObject else { return }

        if asset.mediaType == .image {
            Task { @MainActor in
                self.updateClip(clipID, transform: { clip in
                    clip.duration = Tokens.Timing.photoDefaultDuration
                    clip.updatedAt = Date()
                }, in: tapeID)
            }
            return
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let avAsset else { return }
            let durationSeconds = CMTimeGetSeconds(avAsset.duration)

            Task { @MainActor in
                self.updateClip(clipID, transform: { clip in
                    clip.duration = durationSeconds
                    clip.updatedAt = Date()
                }, in: tapeID)
            }

            if let urlAsset = avAsset as? AVURLAsset {
                self.generateThumbAndDuration(for: urlAsset.url, clipID: clipID, tapeID: tapeID)
            } else {
                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                    guard let cg else { return }
                    let ui = UIImage(cgImage: cg)
                    Task { @MainActor in
                        self.updateClip(clipID, transform: { $0.thumbnail = ui.jpegData(compressionQuality: 0.8) }, in: tapeID)
                    }
                }
            }
        }
    }

    private func processAlbumAssociation(tapeID: UUID, tape: Tape, assetIdentifiers: [String]) async {
        guard !assetIdentifiers.isEmpty else { return }
        do {
            let freshTape = await MainActor.run { self.getTape(by: tapeID) } ?? tape
            let association = try await albumService.ensureAlbum(for: freshTape)
            let albumIdentifier = association.albumLocalIdentifier
            if freshTape.albumLocalIdentifier != albumIdentifier {
                await MainActor.run {
                    self.updateTapeAlbumIdentifier(albumIdentifier, for: tapeID)
                }
            }
            try await albumService.addAssets(withIdentifiers: assetIdentifiers, to: albumIdentifier)
            await MainActor.run {
                self.albumAssociationError = nil
            }
        } catch {
            TapesLog.photos.error("Album association failed for tape \(tapeID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.albumAssociationError = error.localizedDescription
            }
        }
    }

    @MainActor
    func updateTapeAlbumIdentifier(_ identifier: String, for tapeID: UUID) {
        guard let index = tapes.firstIndex(where: { $0.id == tapeID }) else { return }
        var tape = tapes[index]
        TapesLog.photos.info("Updating tape \(tapeID.uuidString, privacy: .public) with album identifier \(identifier, privacy: .public).")
        tape.albumLocalIdentifier = identifier
        tapes[index] = tape
        autoSave()
    }

    private func scheduleAlbumDeletionIfNeeded(for tape: Tape) {
        guard FeatureFlags.deleteAssociatedPhotoAlbum,
              let albumId = tape.albumLocalIdentifier,
              !albumId.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            do {
                try await self?.albumService.deleteAlbum(withLocalIdentifier: albumId)
            } catch {
                TapesLog.photos.error("Failed to delete Photos album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleAlbumRenameIfNeeded(previousTape: Tape, updatedTape: Tape) {
        let previousTitle = previousTape.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = updatedTape.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previousTitle != newTitle else { return }
        guard let albumId = updatedTape.albumLocalIdentifier, !albumId.isEmpty else {
            TapesLog.photos.warning("Skipping album rename; tape \(updatedTape.id.uuidString, privacy: .public) has no stored album identifier.")
            return
        }
        
        TapesLog.photos.info("Scheduling Photos album rename for tape \(updatedTape.id.uuidString, privacy: .public) (albumId: \(albumId, privacy: .public)).")
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                TapesLog.photos.info("Attempting Photos album rename for tape \(updatedTape.id.uuidString, privacy: .public).")
                if let newIdentifier = try await self.albumService.renameAlbum(withLocalIdentifier: albumId, toMatch: updatedTape), newIdentifier != albumId {
                    await MainActor.run {
                        self.updateTapeAlbumIdentifier(newIdentifier, for: updatedTape.id)
                        self.albumAssociationError = nil
                    }
                } else {
                    await MainActor.run {
                        self.albumAssociationError = nil
                    }
                }
            } catch let error as TapeAlbumServiceError {
                TapesLog.photos.error("Failed to rename Photos album for tape \(updatedTape.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    switch error {
                    case .insufficientPermissions:
                        self.albumAssociationError = "Give Tapes 'All Photos' access (Settings > Privacy & Security > Photos > Tapes) so album titles stay in sync."
                    default:
                        self.albumAssociationError = error.localizedDescription
                    }
                }
            } catch {
                TapesLog.photos.error("Failed to rename Photos album for tape \(updatedTape.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.albumAssociationError = error.localizedDescription
                }
            }
        }
    }

    /// Restore invariant: ensure empty tape exists at top after loading
    public func restoreEmptyTapeInvariant() {
        // Check if first tape is empty
        if let firstTape = tapes.first, firstTape.clips.isEmpty {
            // First tape is already empty, no action needed
            return
        }
        
        // No empty tape at top, insert one
        insertEmptyTapeAtTop()
    }
}
