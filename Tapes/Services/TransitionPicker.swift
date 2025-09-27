    import Foundation

// MARK: - Transition Picker Service

public class TransitionPicker {
    private let seed: UInt64
    private var randomGenerator: SeededRandomNumberGenerator
    
    public init(seed: UInt64) {
        self.seed = seed
        self.randomGenerator = SeededRandomNumberGenerator(seed: seed)
    }
    
    public init(tapeId: UUID) {
        // Use tape ID as seed for consistent results
        // Use absolute value to ensure positive UInt64
        self.seed = UInt64(abs(tapeId.hashValue))
        self.randomGenerator = SeededRandomNumberGenerator(seed: self.seed)
    }
    
    /// Picks a transition type based on the tape's transition setting
    public func pickTransition(for tape: Tape, at clipIndex: Int) -> TransitionType {
        switch tape.transition {
        case .none:
            return .none
        case .crossfade:
            return .crossfade
        case .slideLR:
            return .slideLR
        case .slideRL:
            return .slideRL
        case .randomise:
            return pickRandomTransition()
        }
    }
    
    /// Picks a transition duration based on the tape's settings
    public func pickTransitionDuration(for tape: Tape, at clipIndex: Int) -> Double {
        let baseDuration = tape.transitionDuration
        
        // For randomise transitions, clamp to 0.5s maximum
        if tape.transition == .randomise {
            return min(baseDuration, 0.5)
        }
        
        return baseDuration
    }
    
    /// Picks a random transition type for randomise mode
    private func pickRandomTransition() -> TransitionType {
        let transitions: [TransitionType] = [.none, .crossfade, .slideLR, .slideRL]
        let randomIndex = Int.random(in: 0..<transitions.count, using: &randomGenerator)
        return transitions[randomIndex]
    }
    
    /// Resets the random generator to the original seed
    public func reset() {
        randomGenerator = SeededRandomNumberGenerator(seed: seed)
    }
    
    /// Gets the current seed value
    public func getSeed() -> UInt64 {
        return seed
    }
}

// MARK: - Seeded Random Number Generator

public struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    public init(seed: UInt64) {
        self.state = seed
    }
    
    public mutating func next() -> UInt64 {
        // Linear congruential generator for deterministic results
        state = (state &* 1103515245 &+ 12345) & 0x7fffffff
        return state
    }
}

// MARK: - Transition Info

public struct TransitionInfo {
    public let type: TransitionType
    public let duration: Double
    public let fromClipIndex: Int
    public let toClipIndex: Int
    
    public init(type: TransitionType, duration: Double, fromClipIndex: Int, toClipIndex: Int) {
        self.type = type
        self.duration = duration
        self.fromClipIndex = fromClipIndex
        self.toClipIndex = toClipIndex
    }
}

// MARK: - Transition Picker Extensions

extension TransitionPicker {
    /// Generates all transition info for a tape
    public func generateTransitionSequence(for tape: Tape) -> [TransitionInfo] {
        var transitions: [TransitionInfo] = []
        
        guard tape.clips.count > 1 else {
            return transitions
        }
        
        for i in 0..<(tape.clips.count - 1) {
            let transitionType = pickTransition(for: tape, at: i)
            let duration = pickTransitionDuration(for: tape, at: i)
            
            let transition = TransitionInfo(
                type: transitionType,
                duration: duration,
                fromClipIndex: i,
                toClipIndex: i + 1
            )
            
            transitions.append(transition)
        }
        
        return transitions
    }
    
    /// Gets transition info for a specific clip transition
    public func getTransitionInfo(for tape: Tape, fromClipIndex: Int) -> TransitionInfo? {
        guard fromClipIndex < tape.clips.count - 1 else {
            return nil
        }
        
        let transitionType = pickTransition(for: tape, at: fromClipIndex)
        let duration = pickTransitionDuration(for: tape, at: fromClipIndex)
        
        return TransitionInfo(
            type: transitionType,
            duration: duration,
            fromClipIndex: fromClipIndex,
            toClipIndex: fromClipIndex + 1
        )
    }
}
