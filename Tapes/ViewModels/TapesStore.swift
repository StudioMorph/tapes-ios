import Foundation
import Photos
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation


// MARK: - Persistence

private actor TapePersistenceActor {
    private let mediaDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.mediaDir = docs.appendingPathComponent("clip_media", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    func save(_ tapes: [Tape], to url: URL) {
        for tape in tapes {
            for clip in tape.clips {
                saveBlobFiles(for: clip)
            }
        }

        let stripped = tapes.map { tape -> Tape in
            var t = tape
            t.clips = t.clips.map { clip in
                var c = clip
                c.thumbnail = nil
                c.imageData = nil
                return c
            }
            return t
        }

        do {
            let data = try JSONEncoder().encode(stripped)
            try data.write(to: url)
        } catch {
            TapesLog.store.error("Failed to save tapes: \(error.localizedDescription)")
        }
    }

    func load(from url: URL) -> [Tape] {
        do {
            let data = try Data(contentsOf: url)
            var tapes = try JSONDecoder().decode([Tape].self, from: data)

            // Migrate: if old JSON had inline blobs, save them as files
            var needsMigration = false
            for tape in tapes {
                for clip in tape.clips where clip.thumbnail != nil || clip.imageData != nil {
                    saveBlobFiles(for: clip)
                    needsMigration = true
                }
            }

            if needsMigration {
                // Strip blobs from in-memory clips (they're now on disk)
                for tIdx in tapes.indices {
                    for cIdx in tapes[tIdx].clips.indices {
                        tapes[tIdx].clips[cIdx].thumbnail = nil
                        tapes[tIdx].clips[cIdx].imageData = nil
                    }
                }
                // Re-save JSON without blobs
                let stripped = tapes.map { $0.removingPlaceholders() }
                if let encoded = try? JSONEncoder().encode(stripped) {
                    try? encoded.write(to: url)
                }
            }

            return tapes
        } catch {
            TapesLog.store.warning("No saved tapes found or failed to load: \(error.localizedDescription)")
            return []
        }
    }

    func deleteBlobs(for clipID: UUID) {
        let thumbURL = mediaDir.appendingPathComponent("\(clipID)_thumb.jpg")
        let imageURL = mediaDir.appendingPathComponent("\(clipID)_image.dat")
        try? FileManager.default.removeItem(at: thumbURL)
        try? FileManager.default.removeItem(at: imageURL)
    }

    func deleteBlobs(for clipIDs: [UUID]) {
        for id in clipIDs { deleteBlobs(for: id) }
    }

    private func saveBlobFiles(for clip: Clip) {
        if let thumb = clip.thumbnail {
            let url = mediaDir.appendingPathComponent("\(clip.id)_thumb.jpg")
            try? thumb.write(to: url)
        }
        if let img = clip.imageData {
            let url = mediaDir.appendingPathComponent("\(clip.id)_image.dat")
            try? img.write(to: url)
        }
    }

    static var mediaDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("clip_media", isDirectory: true)
    }
}

// MARK: - TapesStore

@MainActor
public class TapesStore: ObservableObject {
    @Published public var tapes: [Tape] = []
    @Published public private(set) var isLoaded = false

    public var myTapes: [Tape] {
        tapes.filter { !$0.isShared }
    }

    public var sharedTapes: [Tape] {
        tapes.filter { $0.isShared }
    }

    /// Number of tapes that have received content (excludes empty placeholder tapes).
    public var contentTapeCount: Int {
        tapes.filter { $0.hasReceivedFirstContent || !$0.clips.isEmpty }.count
    }
    @Published public var selectedTape: Tape?
    @Published public var showingSettingsSheet = false
    @Published public var latestInsertedTapeID: UUID?
    @Published public var pendingTapeRevealID: UUID?
    @Published public var albumAssociationError: String?
    @Published public var jigglingTapeID: UUID? = nil

    // MARK: - Floating Clip (drag-to-move)
    @Published public var floatingClip: Clip? = nil
    @Published public var floatingSourceTapeID: UUID? = nil
    @Published public var floatingSourceIndex: Int? = nil
    @Published public var floatingPosition: CGPoint = .zero
    @Published public var floatingOriginalFrame: CGRect = .zero
    @Published public var floatingThumbSize: CGSize = .zero
    @Published public var floatingDragDidEnd = false
    @Published public var isFloatingDragActive = false

    public var isFloatingClip: Bool { floatingClip != nil }
    @Published public var dropCompletedTapeID: UUID? = nil
    @Published public var dropCompletedAtIndex: Int? = nil

    public func liftClip(_ clip: Clip, fromTape tapeID: UUID, atIndex index: Int, originFrame: CGRect, thumbSize: CGSize) {
        if floatingClip != nil {
            returnFloatingClip()
        }
        floatingClip = clip
        floatingSourceTapeID = tapeID
        floatingSourceIndex = index
        floatingOriginalFrame = originFrame
        floatingThumbSize = thumbSize
        floatingPosition = CGPoint(x: originFrame.midX, y: originFrame.midY)
        isFloatingDragActive = true
    }

    public func returnFloatingClip() {
        clearFloatingState()
    }

    public func dropFloatingClip(onTape tapeID: UUID, atIndex index: Int, afterClipID: UUID? = nil, beforeClipID: UUID? = nil) {
        guard let clip = floatingClip else {
            clearFloatingState()
            return
        }

        guard var tape = getTape(by: tapeID) else {
            clearFloatingState()
            return
        }

        let removedIndex = tape.clips.firstIndex(where: { $0.id == clip.id })
        tape.removeClip(clip)

        let insertionIndex: Int
        if let afterID = afterClipID,
           let afterIdx = tape.clips.firstIndex(where: { $0.id == afterID }) {
            insertionIndex = afterIdx + 1
        } else if let beforeID = beforeClipID,
                  let beforeIdx = tape.clips.firstIndex(where: { $0.id == beforeID }) {
            insertionIndex = beforeIdx
        } else {
            var adjusted = index
            if let ri = removedIndex, ri < index {
                adjusted = max(0, adjusted - 1)
            }
            insertionIndex = min(adjusted, tape.clips.count)
        }

        tape.addClip(clip, at: insertionIndex)
        updateTape(tape)
        dropCompletedTapeID = tapeID
        dropCompletedAtIndex = insertionIndex + 1

        clearFloatingState()
    }

    private func clearFloatingState() {
        floatingClip = nil
        floatingSourceTapeID = nil
        floatingSourceIndex = nil
        floatingPosition = .zero
        floatingOriginalFrame = .zero
        floatingThumbSize = .zero
        isFloatingDragActive = false
    }
    
    private struct AlbumAssociationQueueEntry {
        let id: UUID
        let task: Task<Void, Never>
    }
    
    private let albumService: TapeAlbumServicing
    private var albumAssociationQueues: [UUID: AlbumAssociationQueueEntry] = [:]
    private let persistenceActor = TapePersistenceActor()
    private var saveTask: Task<Void, Never>?
    private let saveDebounce: TimeInterval = 0.35
    private var metadataQueue: [() async -> Void] = []
    private var activeMetadataTasks = 0
    private static let maxConcurrentMetadata = 8
    private var pendingClipUpdates: [(clipID: UUID, tapeID: UUID, transform: (inout Clip) -> Void)] = []
    private var batchUpdateTask: Task<Void, Never>?
    
    // MARK: - Persistence
    private let persistenceKey = "SavedTapes"
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var persistenceURL: URL {
        documentsDirectory.appendingPathComponent("tapes.json")
    }
    
    public init(albumService: TapeAlbumServicing = TapeAlbumService()) {
        self.albumService = albumService
        loadTapesFromDisk()
    }
    
    #if DEBUG
    func resetForDebug() {
        tapes = [Tape(
            title: "New Tape",
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
        scheduleMediaCleanup(for: tape.clips.map(\.id))
        tapes.removeAll { $0.id == tape.id }
        autoSave()
    }

    public func deleteTape(by id: UUID) {
        if let tape = getTape(by: id) {
            scheduleAlbumDeletionIfNeeded(for: tape)
            scheduleMediaCleanup(for: tape.clips.map(\.id))
        }
        tapes.removeAll { $0.id == id }
        autoSave()
    }
    
    // MARK: - Selected Tape Management
    
    public func selectTape(_ tape: Tape) {
        print("🔧 TapesStore.selectTape called for: \(tape.title)")
        selectedTape = tape
        showingSettingsSheet = true
        print("🔧 showingSettingsSheet set to: \(showingSettingsSheet)")
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
        
        if index < tape.clips.count {
            let clip = tape.clips[index]
            scheduleMediaCleanup(for: [clip.id])
            tape.clips.remove(at: index)
        }
        
        if tape.clips.isEmpty {
            tape.clips = []
        }
        
        updateTape(tape)
    }
    
    public func deleteClip(from tapeId: UUID, clip: Clip) {
        guard var tape = getTape(by: tapeId) else { return }

        let albumId = tape.albumLocalIdentifier
        let assetId = clip.assetLocalId

        tape.clips.removeAll { $0.id == clip.id }
        scheduleMediaCleanup(for: [clip.id])

        if tape.clips.isEmpty {
            tape.clips = []
        }

        updateTape(tape)

        if let albumId, let assetId, !assetId.isEmpty {
            Task {
                try? await albumService.removeAssets(withIdentifiers: [assetId], from: albumId)
            }
        }
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

    // MARK: - Clip Building Helpers

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
        let thumbnailData = image.jpegData(compressionQuality: 0.9)
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

    private func scheduleMediaCleanup(for clipIDs: [UUID]) {
        guard !clipIDs.isEmpty else { return }
        let actor = persistenceActor
        Task.detached(priority: .utility) {
            await actor.deleteBlobs(for: clipIDs)
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
    /// Returns a binding to a tape by ID, for use in views that need a `Binding<Tape>`.
    public func bindingForTape(id: UUID) -> Binding<Tape>? {
        guard tapes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                guard let idx = self.tapes.firstIndex(where: { $0.id == id }) else {
                    return Tape(title: "")
                }
                return self.tapes[idx]
            },
            set: {
                guard let idx = self.tapes.firstIndex(where: { $0.id == id }) else { return }
                self.tapes[idx] = $0
            }
        )
    }

    /// Returns an existing shared tape for a given remote tape ID, if any.
    public func sharedTape(forRemoteId remoteTapeId: String) -> Tape? {
        tapes.first { $0.shareInfo?.remoteTapeId == remoteTapeId }
    }

    /// Adds or updates a shared tape in the store.
    public func addSharedTape(_ tape: Tape) {
        if let idx = tapes.firstIndex(where: { $0.shareInfo?.remoteTapeId == tape.shareInfo?.remoteTapeId }) {
            tapes[idx] = tape
        } else {
            tapes.append(tape)
        }
        autoSave()
    }

    /// Creates a collaborative fork of a tape in the Shared/Collaborating segment.
    /// The original tape in My Tapes stays untouched.
    /// A separate Photos album "[Name] - Collab" is created for the fork.
    public func forkTapeForCollaboration(
        _ sourceTape: Tape,
        remoteTapeId: String,
        shareId: String,
        ownerName: String?
    ) {
        if tapes.contains(where: { $0.shareInfo?.remoteTapeId == remoteTapeId }) {
            return
        }

        var forkedClips = sourceTape.clips.filter { !$0.isPlaceholder }
        for i in forkedClips.indices {
            forkedClips[i].isSynced = true
        }

        let collabTitle = "\(sourceTape.title) - Collab"

        let info = ShareInfo(
            shareId: shareId,
            ownerName: ownerName,
            mode: "collaborative",
            expiresAt: nil,
            remoteTapeId: remoteTapeId
        )

        let fork = Tape(
            title: collabTitle,
            orientation: sourceTape.orientation,
            scaleMode: sourceTape.scaleMode,
            transition: sourceTape.transition,
            transitionDuration: sourceTape.transitionDuration,
            seamTransitions: sourceTape.seamTransitions,
            clips: forkedClips,
            hasReceivedFirstContent: !forkedClips.isEmpty,
            backgroundMusicMood: sourceTape.backgroundMusicMood,
            backgroundMusicVolume: sourceTape.backgroundMusicVolume,
            exportOrientation: sourceTape.exportOrientation,
            blurExportBackground: sourceTape.blurExportBackground,
            livePhotosAsVideo: sourceTape.livePhotosAsVideo,
            livePhotosMuted: sourceTape.livePhotosMuted,
            shareInfo: info
        )

        tapes.append(fork)
        autoSave()

        if !forkedClips.isEmpty {
            associateClipsWithAlbum(tapeID: fork.id, clips: forkedClips)
        }
    }

    /// Merges new clips into an existing shared tape (for incoming contributions).
    public func mergeClipsIntoSharedTape(remoteTapeId: String, newClips: [Clip]) {
        guard let idx = tapes.firstIndex(where: { $0.shareInfo?.remoteTapeId == remoteTapeId }) else { return }

        let existingIds = Set(tapes[idx].clips.map { $0.id })
        let uniqueNewClips = newClips.filter { !existingIds.contains($0.id) }

        guard !uniqueNewClips.isEmpty else { return }

        tapes[idx].clips.append(contentsOf: uniqueNewClips)
        tapes[idx].updatedAt = Date()
        autoSave()
    }

    public func markClipSynced(_ clipId: UUID, inTape tapeId: UUID) {
        guard let tapeIdx = tapes.firstIndex(where: { $0.id == tapeId }),
              let clipIdx = tapes[tapeIdx].clips.firstIndex(where: { $0.id == clipId }) else { return }
        tapes[tapeIdx].clips[clipIdx].isSynced = true
        autoSave()
    }

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
                let clip = makeVideoClip(url: url, duration: duration, assetIdentifier: assetIdentifier)
                newClips.append(clip)
            case let .photo(image, assetIdentifier, isLivePhoto, _, _):
                if var imageClip = makeImageClip(image: image, assetIdentifier: assetIdentifier) {
                    imageClip.isLivePhoto = isLivePhoto
                    newClips.append(imageClip)
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
        for clip in newClips where clip.clipType == .video {
            generateThumbAndDuration(for: clip, tapeID: tapeID)
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
                let clip = makeVideoClip(url: url, duration: duration, assetIdentifier: assetIdentifier)
                newClips.append(clip)
            case let .photo(image, assetIdentifier, isLivePhoto, _, _):
                if var imageClip = makeImageClip(image: image, assetIdentifier: assetIdentifier) {
                    imageClip.isLivePhoto = isLivePhoto
                    newClips.append(imageClip)
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
        
        for clip in newClips where clip.clipType == .video {
            generateThumbAndDuration(for: clip, tapeID: tape.wrappedValue.id)
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
        
        for clip in newClips where clip.clipType == .video {
            generateThumbAndDuration(for: clip, tapeID: tapeID)
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
    
    /// Generate thumbnail and duration for a clip using lightweight metadata when possible.
    func generateThumbAndDuration(for clip: Clip, tapeID: UUID) {
        guard clip.clipType == .video else { return }
        let needsDuration = clip.duration <= 0
        let needsThumbnail = !clip.hasThumbnail
        guard needsDuration || needsThumbnail else { return }

        let clipID = clip.id
        let assetLocalId = clip.assetLocalId
        let localURL = clip.localURL

        enqueueMetadataWork { [weak self] in
            guard let self else { return }

            var asset: PHAsset?
            if let assetLocalId {
                for attempt in 0..<3 {
                    asset = Self.fetchPHAsset(localIdentifier: assetLocalId)
                    if asset != nil { break }
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }

            if let asset {
                if needsDuration, asset.duration > 0 {
                    await self.enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { $0.duration = asset.duration }
                }
                if needsThumbnail, let thumbnail = await Self.requestThumbnail(for: asset) {
                    await self.enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { $0.thumbnail = thumbnail.jpegData(compressionQuality: 0.8) }
                }
                return
            }

            if let url = localURL {
                await self.processAssetMetadata(url: url, clipID: clipID, tapeID: tapeID, needsDuration: needsDuration, needsThumbnail: needsThumbnail)
            } else {
                TapesLog.store.error("Thumbnail generation failed: no PHAsset or localURL for clip \(clipID)")
            }
        }
    }

    private func enqueueMetadataWork(_ work: @escaping () async -> Void) {
        metadataQueue.append(work)
        drainMetadataQueue()
    }

    private static let metadataSlotTimeout: UInt64 = 20_000_000_000 // 20 seconds

    private func drainMetadataQueue() {
        guard activeMetadataTasks < Self.maxConcurrentMetadata, !metadataQueue.isEmpty else { return }
        let work = metadataQueue.removeFirst()
        activeMetadataTasks += 1
        Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                let done = AtomicFlag()

                group.addTask {
                    await work()
                    _ = done.testAndSet()
                }

                group.addTask {
                    try? await Task.sleep(nanoseconds: Self.metadataSlotTimeout)
                    if done.testAndSet() {
                        TapesLog.store.warning("Metadata slot timed out after 20s — freeing slot")
                    }
                }

                _ = await group.next()
                group.cancelAll()
            }

            await MainActor.run { [weak self] in
                self?.activeMetadataTasks -= 1
                self?.drainMetadataQueue()
            }
        }
    }

    @MainActor
    private func enqueueBatchUpdate(clipID: UUID, tapeID: UUID, transform: @escaping (inout Clip) -> Void) {
        pendingClipUpdates.append((clipID: clipID, tapeID: tapeID, transform: transform))
        scheduleBatchFlush()
    }

    private func scheduleBatchFlush() {
        guard batchUpdateTask == nil else { return }
        batchUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self?.flushBatchUpdates()
        }
    }

    private func flushBatchUpdates() {
        batchUpdateTask = nil
        guard !pendingClipUpdates.isEmpty else { return }
        let updates = pendingClipUpdates
        pendingClipUpdates.removeAll()

        var mutatedTapeIndices: Set<Int> = []
        for update in updates {
            guard let tIndex = tapes.firstIndex(where: { $0.id == update.tapeID }),
                  let cIndex = tapes[tIndex].clips.firstIndex(where: { $0.id == update.clipID }) else { continue }
            update.transform(&tapes[tIndex].clips[cIndex])
            mutatedTapeIndices.insert(tIndex)
        }

        if !mutatedTapeIndices.isEmpty {
            autoSave()
        }
    }

    private func processAssetMetadata(
        url: URL,
        clipID: UUID,
        tapeID: UUID,
        needsDuration: Bool,
        needsThumbnail: Bool
    ) async {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )

        do {
            if needsDuration {
                let duration = try await asset.load(.duration)
                await self.enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { $0.duration = duration.seconds }
            }

            guard needsThumbnail else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)

            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                guard let cg else { return }
                let ui = UIImage(cgImage: cg)
                Task { @MainActor [weak self] in
                    self?.enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { $0.thumbnail = ui.jpegData(compressionQuality: 0.8) }
                }
            }
        } catch {
            TapesLog.store.error("Failed to load thumbnail/duration: \(error.localizedDescription)")
        }
    }

    nonisolated private static func fetchPHAsset(localIdentifier: String) -> PHAsset? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return fetch.firstObject
    }

    private static let thumbnailTimeout: UInt64 = 10_000_000_000 // 10 seconds

    nonisolated private static func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        let requestIDBox = UnsafeSendableBox<PHImageRequestID>()

        return await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                    let resumed = AtomicFlag()
                    let options = PHImageRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.resizeMode = .fast
                    options.isSynchronous = false

                    let targetSize = CGSize(width: 480, height: 480)
                    let reqID = PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        if resumed.testAndSet() {
                            continuation.resume(returning: image)
                        }
                    }
                    requestIDBox.value = reqID
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: thumbnailTimeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            if let reqID = requestIDBox.value {
                PHImageManager.default().cancelImageRequest(reqID)
            }
            return result
        }
    }
    
    // MARK: - Persistence Methods
    
    /// Save tapes to disk.
    /// Snapshot construction (which copies blob data) is deferred into the
    /// detached task so the main thread only captures a CoW array reference.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = tapes
        let url = persistenceURL
        let actor = persistenceActor
        let delay = saveDebounce
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let sanitized = snapshot.map { $0.removingPlaceholders() }
            await actor.save(sanitized, to: url)
        }
    }
    
    /// Load tapes from disk
    private func loadTapesFromDisk() {
        let url = persistenceURL
        let actor = persistenceActor
        Task(priority: .utility) {
            let loaded = await actor.load(from: url)
            applyLoadedTapes(loaded)
        }
    }
    
    /// Auto-save when tapes change
    private func autoSave() {
        scheduleSave()
    }

    private func applyLoadedTapes(_ loaded: [Tape]) {
        tapes = loaded

        if tapes.isEmpty {
            let newReel = Tape(
                title: "New Tape",
                orientation: .portrait,
                scaleMode: .fit,
                transition: .none,
                transitionDuration: 0.5,
                clips: [],
                hasReceivedFirstContent: false
            )
            tapes.append(newReel)
        }

        restoreEmptyTapeInvariant(animated: false)
        isLoaded = true

        Task(priority: .background) { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.restoreMissingClipMetadata()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.scheduleLegacyAlbumAssociation()
        }
    }
    
    // MARK: - Empty Tape Management
    
    /// Insert a new empty tape at index 0
    public func insertEmptyTapeAtTop(animated: Bool = true) {
        let newEmptyTape = Tape(
            title: "New Tape",
            orientation: .portrait,
            scaleMode: .fit,
            transition: .none,
            transitionDuration: 0.5,
            clips: [],
            hasReceivedFirstContent: false
        )

        if animated {
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
        } else {
            tapes.insert(newEmptyTape, at: 0)
        }
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

                if clip.clipType == .video && (clip.duration <= 0 || !clip.hasThumbnail) {
                    generateThumbAndDuration(for: clip, tapeID: tape.id)
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
        guard let asset = Self.fetchPHAsset(localIdentifier: assetLocalId) else { return }

        if asset.mediaType == .image {
            enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { clip in
                clip.duration = Tokens.Timing.photoDefaultDuration
                clip.updatedAt = Date()
            }
            return
        }

        let durationSeconds = asset.duration
        if durationSeconds > 0 {
            enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { clip in
                clip.duration = durationSeconds
                clip.updatedAt = Date()
            }
        }

        enqueueMetadataWork { [weak self] in
            guard let self else { return }
            if let thumbnail = await Self.requestThumbnail(for: asset) {
                await self.enqueueBatchUpdate(clipID: clipID, tapeID: tapeID) { $0.thumbnail = thumbnail.jpegData(compressionQuality: 0.8) }
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
    public func restoreEmptyTapeInvariant(animated: Bool = true) {
        if let firstTape = tapes.first, firstTape.clips.isEmpty {
            return
        }
        insertEmptyTapeAtTop(animated: animated)
    }
}
