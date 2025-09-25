import Foundation
import Photos
import SwiftUI

// MARK: - TapesStore

@MainActor
public class TapesStore: ObservableObject {
    @Published public var tapes: [Tape] = []
    @Published public var selectedTape: Tape?
    
    public init() {
        // Create one empty "New Tape" on init as per acceptance criteria
        _ = createNewTape()
    }
    
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
}
