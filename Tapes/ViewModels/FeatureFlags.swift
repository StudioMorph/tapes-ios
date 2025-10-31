import Foundation

enum FeatureFlags {
    /// Controls whether deleting a Tape also deletes its associated Photos album.
    /// Default is `false` to avoid changing current behaviour until the feature is fully vetted.
    static var deleteAssociatedPhotoAlbum: Bool {
        return true
    }
    
    /// Controls the new playback engine with hybrid loading strategy.
    /// Phase 1: Hybrid loading (parallel local, sequential Photos), time window, skip behavior with placeholders.
    /// Default is `false` for safe rollout.
    static var playbackEngineV2Phase1: Bool {
        return true
    }
    
    /// Controls skip behavior within the new playback engine.
    /// Can be disabled independently if skip behavior is problematic.
    static var playbackEngineV2SkipBehavior: Bool {
        return playbackEngineV2Phase1 && true
    }
    
    /// Controls hybrid loading strategy within the new playback engine.
    /// Can be disabled to fall back to simple parallel loading.
    static var playbackEngineV2HybridLoading: Bool {
        return playbackEngineV2Phase1 && true
    }
    
    /// Controls Phase 2 features: Progressive extension, background prefetch, large tape support.
    static var playbackEngineV2Phase2: Bool {
        return playbackEngineV2Phase1 && true // Enabled for testing
    }
    
    /// Controls Phase 3 features: 3D transitions, playback speed control, advanced controls.
    static var playbackEngineV2Phase3: Bool {
        return playbackEngineV2Phase1 && playbackEngineV2Phase2 && true // Enabled for testing
    }
}
