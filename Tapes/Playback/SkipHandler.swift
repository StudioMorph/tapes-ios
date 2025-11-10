import Foundation

/// Manages skip behavior during playback - tracks which clips are skipped and provides navigation
final class SkipHandler {
    
    // MARK: - Properties
    
    private var skippedIndices: Set<Int>
    private var readyIndices: Set<Int>
    private let allClipIndices: [Int]
    
    private var lastSkipTime: Date = .distantPast
    private let skipDebounceInterval: TimeInterval = 0.5
    
    // MARK: - Initialization
    
    init(
        skippedIndices: Set<Int>,
        readyIndices: Set<Int>,
        allClipIndices: [Int]
    ) {
        self.skippedIndices = skippedIndices
        self.readyIndices = readyIndices
        self.allClipIndices = allClipIndices
    }
    
    // MARK: - Public API
    
    /// Check if a clip should be skipped
    func shouldSkip(clipIndex: Int) -> Bool {
        return skippedIndices.contains(clipIndex)
    }
    
    /// Get the next ready clip index after the given index
    func nextReadyClip(after index: Int) -> Int? {
        // Find next ready clip in sequence
        for i in (index + 1)..<allClipIndices.count {
            if readyIndices.contains(i) {
                return i
            }
        }
        return nil // No more ready clips
    }
    
    /// Get the previous ready clip index before the given index
    func previousReadyClip(before index: Int) -> Int? {
        // Find previous ready clip in sequence
        for i in (0..<index).reversed() {
            if readyIndices.contains(i) {
                return i
            }
        }
        return nil // No previous ready clips
    }
    
    /// Check if skipping is allowed (debouncing)
    func canSkip() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastSkipTime) >= skipDebounceInterval else {
            TapesLog.player.warning("SkipHandler: Skip debounced (too rapid)")
            return false
        }
        lastSkipTime = now
        return true
    }
    
    /// Get skip statistics
    func getSkipStats() -> (skipped: Int, ready: Int, total: Int) {
        return (skippedIndices.count, readyIndices.count, allClipIndices.count)
    }
    
    /// Check if there are consecutive skipped clips starting at index
    func hasConsecutiveSkips(startingAt index: Int) -> (count: Int, indices: [Int]) {
        var consecutive: [Int] = [index]
        var current = index + 1
        
        while current < allClipIndices.count && skippedIndices.contains(current) {
            consecutive.append(current)
            current += 1
        }
        
        return (consecutive.count, consecutive)
    }
    
    /// Get all ready clip indices in order
    func getAllReadyIndices() -> [Int] {
        return allClipIndices.filter { readyIndices.contains($0) }
    }
    
    /// Update ready indices when new assets become available
    /// This removes newly-ready clips from skippedIndices and adds them to readyIndices
    func updateReadyIndices(_ newReadyIndices: Set<Int>) {
        // Remove newly-ready clips from skipped indices
        skippedIndices.subtract(newReadyIndices)
        // Add newly-ready clips to ready indices
        readyIndices.formUnion(newReadyIndices)
    }
}

