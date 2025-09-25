import Foundation

/// Deterministic random transition picker seeded by Tape UUID.
/// Pool includes: .none, .crossfade, .slideLR, .slideRL.
enum TransitionPicker {
    static func sequenceForTape(tapeId: UUID, boundaries: Int) -> [TransitionStyle] {
        var rng = SeededGenerator(seed: UInt64(tapeId.hashValue))
        let pool: [TransitionStyle] = [.none, .crossfade, .slideLR, .slideRL]
        return (0..<max(0,boundaries)).map { _ in pool.randomElement(using: &rng)! }
    }
    /// Clamp for Randomise to keep snappy feel.
    static func clampedDuration(_ requested: Double) -> Double { min(requested, 0.5) }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        // Use the same LCG as the Tapes module for consistency
        state = (state &* 1103515245 &+ 12345) & 0x7fffffff
        return state
    }
}
