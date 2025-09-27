import Foundation
import SwiftUI

// MARK: - Player Composer Service

public class PlayerComposer: ObservableObject {
    @Published public var isPlaying: Bool = false
    @Published public var currentClipIndex: Int = 0
    @Published public var playbackProgress: Double = 0.0
    @Published public var currentTransition: TransitionInfo?
    
    private let tape: Tape
    private let transitionPicker: TransitionPicker
    private var playbackTimer: Timer?
    private var transitionSequence: [TransitionInfo] = []
    
    public init(tape: Tape) {
        self.tape = tape
        self.transitionPicker = TransitionPicker(tapeId: tape.id)
        self.transitionSequence = transitionPicker.generateTransitionSequence(for: tape)
        
        // Ensure currentClipIndex is valid
        if tape.clips.isEmpty {
            self.currentClipIndex = 0
        } else {
            self.currentClipIndex = min(self.currentClipIndex, max(0, tape.clips.count - 1))
        }
    }
    
    // MARK: - Playback Control
    
    public func play() {
        guard !tape.clips.isEmpty else { 
            print("⚠️ PlayerComposer: Cannot play empty tape")
            return 
        }
        
        isPlaying = true
        startPlaybackTimer()
    }
    
    public func pause() {
        isPlaying = false
        stopPlaybackTimer()
    }
    
    public func restart() {
        currentClipIndex = 0
        playbackProgress = 0.0
        currentTransition = nil
        transitionPicker.reset()
        transitionSequence = transitionPicker.generateTransitionSequence(for: tape)
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    // MARK: - Playback State
    
    public var currentClip: Clip? {
        guard !tape.clips.isEmpty && currentClipIndex >= 0 && currentClipIndex < tape.clips.count else { 
            print("⚠️ PlayerComposer: Invalid currentClipIndex = \(currentClipIndex), clips.count = \(tape.clips.count)")
            return nil 
        }
        return tape.clips[currentClipIndex]
    }
    
    public var totalDuration: Double {
        let clipDuration = 5.0 // Default clip duration
        let totalClipTime = Double(tape.clips.count) * clipDuration
        let totalTransitionTime = transitionSequence.reduce(0.0) { $0 + $1.duration }
        return totalClipTime + totalTransitionTime
    }
    
    public var currentTime: Double {
        let clipDuration = 5.0 // Default clip duration
        let clipTime = Double(currentClipIndex) * clipDuration
        let transitionTime = transitionSequence.prefix(currentClipIndex).reduce(0.0) { $0 + $1.duration }
        let currentClipProgress = playbackProgress * clipDuration
        return clipTime + transitionTime + currentClipProgress
    }
    
    public var progress: Double {
        guard totalDuration > 0 else { return 0.0 }
        return currentTime / totalDuration
    }
    
    // MARK: - Transition Management
    
    public func getCurrentTransition() -> TransitionInfo? {
        guard currentClipIndex < transitionSequence.count else { return nil }
        return transitionSequence[currentClipIndex]
    }
    
    public func getNextTransition() -> TransitionInfo? {
        guard currentClipIndex + 1 < transitionSequence.count else { return nil }
        return transitionSequence[currentClipIndex + 1]
    }
    
    // MARK: - Private Methods
    
    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlayback()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlayback() {
        guard isPlaying else { return }
        
        let clipDuration = 5.0 // Default clip duration
        playbackProgress += 0.1 / clipDuration
        
        if playbackProgress >= 1.0 {
            // Move to next clip
            playbackProgress = 0.0
            currentClipIndex += 1
            
            print("🔍 PlayerComposer: Moved to clip \(currentClipIndex), total clips = \(tape.clips.count)")
            
            // Check if we've reached the end
            if currentClipIndex >= tape.clips.count {
                // End of tape
                isPlaying = false
                stopPlaybackTimer()
                // Safely set currentClipIndex to last valid index
                currentClipIndex = max(0, tape.clips.count - 1)
                playbackProgress = 1.0
                print("🔍 PlayerComposer: Reached end, set currentClipIndex to \(currentClipIndex)")
            } else {
                // Update current transition
                currentTransition = getCurrentTransition()
            }
        }
    }
}

// MARK: - Player Composer Extensions

extension PlayerComposer {
    /// Gets the visual representation of the current transition
    public func getTransitionVisual() -> TransitionVisual? {
        guard let transition = getCurrentTransition() else { return nil }
        
        return TransitionVisual(
            type: transition.type,
            duration: transition.duration,
            progress: playbackProgress
        )
    }
    
    /// Gets the next transition visual for preview
    public func getNextTransitionVisual() -> TransitionVisual? {
        guard let transition = getNextTransition() else { return nil }
        
        return TransitionVisual(
            type: transition.type,
            duration: transition.duration,
            progress: 0.0
        )
    }
}

// MARK: - Transition Visual

public struct TransitionVisual {
    public let type: TransitionType
    public let duration: Double
    public let progress: Double
    
    public init(type: TransitionType, duration: Double, progress: Double) {
        self.type = type
        self.duration = duration
        self.progress = progress
    }
    
    public var isActive: Bool {
        return progress > 0.0 && progress < 1.0
    }
    
    public var displayName: String {
        switch type {
        case .none:
            return "None"
        case .crossfade:
            return "Crossfade"
        case .slideLR:
            return "Slide L→R"
        case .slideRL:
            return "Slide R→L"
        case .randomise:
            return "Random"
        }
    }
}

// MARK: - Player Composer Preview

extension PlayerComposer {
    /// Creates a preview composer for testing
    public static func preview(tape: Tape) -> PlayerComposer {
        let composer = PlayerComposer(tape: tape)
        return composer
    }
}
