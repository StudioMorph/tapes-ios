# Tape Player - From Scratch Design
## Complete Rebuild with Bulletproof Logic & Performance

---

## Core Principle: Zero Recycling, Fresh Architecture

**What We Keep (Data Only)**:
- `Tape` model (data structure)
- `Clip` model (data structure)
- `TransitionType` enum (transition definitions)

**What We Build Fresh (No Recycling)**:
- Asset loading system (from scratch)
- Composition building (from scratch)
- Player engine (from scratch)
- State management (from scratch)
- Transition rendering (from scratch)
- UI layer (from scratch)

---

## Architecture Overview

### Design Goals
1. **Bulletproof Logic**: Comprehensive error handling, state validation, edge case coverage
2. **Performance**: Optimized memory usage, efficient asset loading, smooth playback
3. **Seamless Transitions**: Transitions rendered perfectly between clips, no glitches
4. **Native APIs**: Use AVFoundation, AVKit, Swift Concurrency directly
5. **Scalability**: Foundation that supports future features (3D transitions, etc.)

---

## Component Architecture (From Scratch)

### 1. MediaAssetResolver
**Purpose**: Load AVAssets from various sources with robust error handling

**Responsibilities**:
- Resolve video assets (local URL or Photos identifier)
- Resolve image assets (encode to video for playback)
- Handle iCloud assets with network access
- Timeout/retry with exponential backoff
- Error classification and reporting

**API**:
```swift
actor MediaAssetResolver {
    func resolveAsset(for clip: Clip) async throws -> ResolvedAsset
    func resolveAssets(for clips: [Clip]) async throws -> [ResolvedAsset]
}

struct ResolvedAsset {
    let asset: AVAsset
    let naturalSize: CGSize
    let duration: CMTime
    let preferredTransform: CGAffineTransform
    let hasAudio: Bool
    let isTemporary: Bool // For encoded images
}
```

**Implementation Notes**:
- Use `actor` for thread safety
- Parallel resolution using `TaskGroup`
- Photos access via `PHImageManager` (native API)
- Image encoding to temporary video files
- Cleanup temporary files on deallocation

**Error Handling**:
- Network timeouts: Retry with backoff
- Photos denied: Clear error message
- Missing asset: Skip with logging
- Encoding failure: Fallback to placeholder or skip

---

### 2. CompositionAssembler
**Purpose**: Build AVFoundation compositions with seamless transitions

**Responsibilities**:
- Create `AVMutableComposition` with video/audio tracks
- Calculate timeline with transition overlaps
- Generate `AVVideoComposition` instructions for transitions
- Apply audio mix for crossfades
- Handle scale modes (fit/fill)
- Support rotation transforms

**API**:
```swift
struct CompositionAssembler {
    func assembleComposition(
        clips: [Clip],
        resolvedAssets: [ResolvedAsset],
        transition: TransitionType,
        transitionDuration: TimeInterval,
        orientation: TapeOrientation,
        scaleMode: ScaleMode
    ) throws -> AssembledComposition
}

struct AssembledComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVMutableAudioMix?
    let timeline: CompositionTimeline
}
```

**Timeline Calculation**:
```
For N clips with transition duration T:
- Clip 0: starts at 0, duration = clipDuration[0]
- Clip 1: starts at clipDuration[0] - T, duration = clipDuration[1] + T (overlap)
- Clip 2: starts at clipDuration[0] - T + clipDuration[1] - T, duration = clipDuration[2] + T
- ...
- Total duration = sum(clipDurations) - (N-1) * T
```

**Transition Instructions**:
- `.none`: Sequential cuts, no overlap
- `.crossfade`: Opacity ramps on both layers during overlap
- `.slideLR`: Transform ramps (slide left-to-right) during overlap
- `.slideRL`: Transform ramps (slide right-to-left) during overlap
- `.randomise`: Deterministic sequence based on tape ID

**Audio Mix**:
- Crossfade: Volume ramps from 1.0 → 0.0 on outgoing, 0.0 → 1.0 on incoming
- Hard cuts: No ramps, abrupt changes

---

### 3. PlaybackEngine
**Purpose**: Own AVPlayer, manage playback state and lifecycle

**Responsibilities**:
- Own single `AVPlayer` instance
- Manage playback state (playing, paused, buffering, finished)
- Observe playback events (time updates, end, stalls)
- Handle interruptions (phone calls, app backgrounding)
- Provide seek functionality with clip boundary awareness
- Track current clip index
- Error reporting

**API**:
```swift
@MainActor
class PlaybackEngine: ObservableObject {
    @Published var isBuffering: Bool
    @Published var isPlaying: Bool
    @Published var currentTime: Double
    @Published var currentClipIndex: Int
    @Published var duration: Double
    @Published var error: PlaybackError?
    
    var player: AVPlayer? { get }
    
    func load(composition: AssembledComposition) async
    func play()
    func pause()
    func seek(to time: Double)
    func seekToClip(at index: Int)
    func teardown()
}
```

**State Management**:
- Single source of truth for playback state
- Thread-safe property updates (@MainActor)
- Clear state transitions (Loading → Ready → Playing → Finished)

**Observers**:
- Time observer: Update currentTime every 0.1s
- End observer: Detect playback completion
- Stall observer: Detect buffering state
- Interruption observer: Handle phone calls, etc.

**Error Handling**:
- Classify errors (network, asset missing, encoding failure)
- Provide user-friendly messages
- Graceful degradation (skip failed clips, continue with available)

---

### 4. TapePlayerController
**Purpose**: Orchestrate asset loading, composition building, and playback

**Responsibilities**:
- Coordinate MediaAssetResolver and CompositionAssembler
- Load all clips in parallel
- Build composition once after all assets ready
- Feed composition to PlaybackEngine
- Handle errors and retries
- Provide progress callbacks

**API**:
```swift
actor TapePlayerController {
    func prepare(tape: Tape) async throws -> AssembledComposition
    func cancel()
}

// Usage in view:
Task {
    do {
        let composition = try await controller.prepare(tape: tape)
        await engine.load(composition: composition)
        engine.play()
    } catch {
        engine.error = error
    }
}
```

**Flow**:
1. Validate tape (has clips, valid settings)
2. Resolve all assets in parallel (TaskGroup)
3. Build composition with transitions
4. Return ready-to-play composition
5. Engine loads and plays

**Error Strategy**:
- If any clip fails: Retry up to 3 times with exponential backoff
- If retry fails: Skip clip, continue with remaining
- If all clips fail: Return error
- Log all failures for debugging

---

### 5. TapePlayerView
**Purpose**: SwiftUI view for full-screen playback

**Responsibilities**:
- Full-screen black background
- VideoPlayer overlay
- Loading overlay (when buffering)
- Controls overlay (play/pause, seek, next/prev, dismiss)
- Auto-hide controls
- Tap to reveal controls
- AirPlay support
- Accessibility

**Implementation**:
```swift
struct TapePlayerView: View {
    @StateObject private var engine = PlaybackEngine()
    @StateObject private var controller = TapePlayerController()
    
    let tape: Tape
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = engine.player {
                VideoPlayer(player: player)
                    .disabled(true)
            }
            
            if engine.isBuffering {
                LoadingOverlay()
            }
            
            if showingControls {
                ControlsOverlay(engine: engine, onDismiss: onDismiss)
            }
        }
        .onAppear {
            Task {
                await prepareAndPlay()
            }
        }
    }
    
    private func prepareAndPlay() async {
        engine.isBuffering = true
        do {
            let composition = try await controller.prepare(tape: tape)
            await engine.load(composition: composition)
            engine.play()
        } catch {
            engine.error = error
        }
        engine.isBuffering = false
    }
}
```

---

## Transition Rendering (Seamless)

### Transition Types Support

**`.none`**:
- No overlap between clips
- Sequential playback
- Hard cuts

**`.crossfade`**:
- Overlap duration = `transitionDuration`
- Opacity ramp on outgoing clip: 1.0 → 0.0
- Opacity ramp on incoming clip: 0.0 → 1.0
- Audio volume ramps (1.0 → 0.0 and 0.0 → 1.0)

**`.slideLR`**:
- Overlap duration = `transitionDuration`
- Outgoing clip: Transform from (0, 0) → (-width, 0)
- Incoming clip: Transform from (width, 0) → (0, 0)
- Opacity fade on both clips during transition

**`.slideRL`**:
- Overlap duration = `transitionDuration`
- Outgoing clip: Transform from (0, 0) → (width, 0)
- Incoming clip: Transform from (-width, 0) → (0, 0)
- Opacity fade on both clips during transition

**`.randomise`**:
- Generate deterministic sequence based on tape ID
- Map each boundary to one of: `.none`, `.crossfade`, `.slideLR`, `.slideRL`
- Apply same sequence logic as export (for parity)

### Implementation Pattern

For each transition boundary:
1. Create `AVVideoCompositionInstruction`
2. Add `AVVideoCompositionLayerInstruction` for outgoing clip
3. Add `AVVideoCompositionLayerInstruction` for incoming clip
4. Apply transform/opacity ramps based on transition type
5. Ensure perfect frame alignment (30fps composition)

---

## Asset Loading (Bulletproof)

### Parallel Loading Strategy

```swift
func resolveAssets(for clips: [Clip]) async throws -> [ResolvedAsset] {
    try await withThrowingTaskGroup(of: (Int, ResolvedAsset?).self) { group in
        // Launch all tasks in parallel
        for (index, clip) in clips.enumerated() {
            group.addTask {
                do {
                    let asset = try await resolveAsset(for: clip)
                    return (index, asset)
                } catch {
                    // Log error, return nil to skip
                    return (index, nil)
                }
            }
        }
        
        // Collect results in order
        var results: [ResolvedAsset?] = Array(repeating: nil, count: clips.count)
        for try await (index, asset) in group {
            results[index] = asset
        }
        
        // Filter out nil (failed clips)
        return results.compactMap { $0 }
    }
}
```

### Photos/iCloud Handling

```swift
func resolveVideoFromPhotos(localIdentifier: String) async throws -> AVAsset {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited else {
        throw AssetError.photosAccessDenied
    }
    
    return try await withCheckedThrowingContinuation { continuation in
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            continuation.resume(throwing: AssetError.assetMissing)
            return
        }
        
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // Critical for iCloud
        options.version = .current
        
        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, info in
            if let asset = asset {
                continuation.resume(returning: asset)
            } else if let error = info?[PHImageErrorKey] as? Error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(throwing: AssetError.unknown)
            }
        }
    }
}
```

### Image-to-Video Encoding

```swift
func encodeImageToVideo(image: UIImage, duration: TimeInterval) async throws -> AVAsset {
    // Create temporary file
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")
    
    // Use AVAssetWriter (native API)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    // ... configure and encode
    // Return AVURLAsset pointing to temp file
}
```

---

## Performance Optimizations

### Memory Management
- **Single Composition**: Build once, play entire tape
- **Asset Cleanup**: Release AVAssets after composition built
- **Temporary Files**: Clean up encoded images after playback
- **Observer Cleanup**: Remove all observers on teardown

### Loading Performance
- **Parallel Resolution**: All clips load simultaneously (TaskGroup)
- **No Sequential Blocking**: No waiting for one clip before starting next
- **Timeout Per Clip**: Each clip has independent timeout (don't block others)

### Playback Performance
- **Fixed Render Size**: 1080×1920 (portrait) or 1920×1080 (landscape)
- **30fps Composition**: Standard frame rate for smooth playback
- **Preferred Forward Buffer**: Set to 2 seconds
- **Automatically Waits to Minimize Stalling**: AVPlayer built-in

### State Management
- **Minimal State**: Only necessary @Published properties
- **Main Actor Isolation**: All UI updates on main thread
- **No Retain Cycles**: Weak references in closures

---

## Error Handling (Bulletproof)

### Error Classification

```swift
enum PlaybackError: Error, LocalizedError {
    case noClips
    case photosAccessDenied
    case assetMissing(clipIndex: Int)
    case encodingFailed(clipIndex: Int)
    case compositionFailed(String)
    case networkTimeout(clipIndex: Int)
    
    var errorDescription: String? {
        switch self {
        case .noClips:
            return "This tape has no clips to play."
        case .photosAccessDenied:
            return "Photos access is required to play this tape."
        case .assetMissing(let index):
            return "Clip \(index + 1) is unavailable."
        case .encodingFailed(let index):
            return "Failed to prepare clip \(index + 1)."
        case .compositionFailed(let reason):
            return "Failed to prepare playback: \(reason)"
        case .networkTimeout(let index):
            return "Clip \(index + 1) is taking too long to load."
        }
    }
}
```

### Recovery Strategies
- **Network Timeout**: Retry with exponential backoff (up to 3 attempts)
- **Asset Missing**: Skip clip, continue with remaining
- **Encoding Failure**: Skip image clip, continue
- **Photos Denied**: Clear error, guide user to settings

### User Feedback
- Loading state: Show "Loading tape..." during preparation
- Error state: Show specific error message with action
- Skip notifications: Optional toast for skipped clips

---

## State Machine (Bulletproof)

### States
```
Idle
  ↓ (prepare called)
Loading
  ↓ (assets resolved + composition built)
Ready
  ↓ (play called)
Playing
  ↓ (pause called)
Paused
  ↓ (play called)
Playing
  ↓ (end reached)
Finished
  ↓ (seek/reset)
Ready/Playing
```

### State Validation
- **Loading**: Can't play, can't seek (show loading)
- **Ready**: Can play, can seek
- **Playing**: Can pause, can seek
- **Paused**: Can play, can seek
- **Finished**: Can seek to restart, can't play (already finished)

### Transition Guards
- Check state before actions
- Clear error messages for invalid transitions
- Log invalid state transitions for debugging

---

## Transition Sequence (Deterministic)

### Randomise Logic
```swift
func generateTransitionSequence(
    tapeID: UUID,
    clipCount: Int,
    baseTransition: TransitionType
) -> [TransitionType] {
    guard baseTransition == .randomise else {
        return Array(repeating: baseTransition, count: clipCount - 1)
    }
    
    // Deterministic RNG seeded by tape ID
    var generator = SeededRNG(seed: tapeID.hashValue)
    let pool: [TransitionType] = [.none, .crossfade, .slideLR, .slideRL]
    
    return (0..<(clipCount - 1)).map { _ in
        pool.randomElement(using: &generator)!
    }
}
```

### Seeded RNG
```swift
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = (state &* 2862933555777941757) &+ 3037000493
        return state
    }
}
```

**Key**: Same sequence every time for same tape ID (parity with export)

---

## Composition Building (From Scratch)

### Track Creation
```swift
// Create video and audio tracks
let videoTrack = composition.addMutableTrack(
    withMediaType: .video,
    preferredTrackID: kCMPersistentTrackID_Invalid
)!

let audioTrack = composition.addMutableTrack(
    withMediaType: .audio,
    preferredTrackID: kCMPersistentTrackID_Invalid
)!
```

### Timeline Calculation
```swift
var currentTime: CMTime = .zero
var instructions: [AVVideoCompositionInstructionProtocol] = []

for (index, asset) in assets.enumerated() {
    let clipDuration = asset.duration
    let clipRange = CMTimeRange(start: .zero, duration: clipDuration)
    
    // Insert into composition
    try videoTrack.insertTimeRange(clipRange, of: asset.videoTrack, at: currentTime)
    if let audio = asset.audioTrack {
        try audioTrack.insertTimeRange(clipRange, of: audio, at: currentTime)
    }
    
    // Calculate transition
    let transition = transitionSequence[safe: index]
    let instruction = createInstruction(
        for: asset,
        at: currentTime,
        transition: transition,
        nextAsset: assets[safe: index + 1]
    )
    instructions.append(instruction)
    
    // Advance time (subtract overlap if transition exists)
    let advance = transition != nil ? 
        CMTimeSubtract(clipDuration, transitionDuration) : 
        clipDuration
    currentTime = CMTimeAdd(currentTime, advance)
}
```

### Transition Instructions
```swift
func createInstruction(
    for asset: ResolvedAsset,
    at time: CMTime,
    transition: TransitionType?,
    nextAsset: ResolvedAsset?
) -> AVVideoCompositionInstructionProtocol {
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: time, duration: asset.duration)
    
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(
        assetTrack: asset.videoTrack
    )
    
    // Apply transforms based on scale mode, rotation
    applyScaleAndRotation(to: layerInstruction, asset: asset)
    
    // If transition, apply ramp
    if let transition = transition, let next = nextAsset {
        applyTransitionRamp(
            to: layerInstruction,
            transition: transition,
            overlapDuration: transitionDuration
        )
    }
    
    instruction.layerInstructions = [layerInstruction]
    return instruction
}
```

---

## Performance Targets

### Time to First Frame Played (TTFMP)
- **Local clips**: ≤ 1.0s p95
- **iCloud clips**: ≤ 3.0s p95
- **Mixed (local + iCloud)**: ≤ 2.5s p95

### Stall Rate
- **≤ 1 stall per 5 minutes** p95
- **Zero stalls** for fully loaded local tapes

### Memory Usage
- **Peak memory**: ≤ 400MB for 30 clips
- **Memory cleanup**: Release assets after composition built
- **Temporary files**: Clean up after playback

### Transition Smoothness
- **60fps rendering**: On capable devices
- **No visible glitches**: At transition boundaries
- **Audio sync**: Perfect alignment with video

---

## Testing Strategy

### Unit Tests
- Asset resolution (local, Photos, iCloud, images)
- Composition building (various clip counts)
- Transition sequence generation (deterministic)
- Timeline calculations (overlaps, durations)
- Error handling (all error paths)

### Integration Tests
- End-to-end playback (load → build → play)
- Transition visual verification
- Seek accuracy
- Clip boundary detection

### Performance Tests
- TTFMP measurement
- Stall rate measurement
- Memory profiling
- Large tape handling (50+ clips)

### Manual Testing
- Local tapes
- iCloud tapes
- Mixed tapes
- Image-only tapes
- Various transition types
- Error scenarios (Photos denied, network offline)

---

## Accessibility

### VoiceOver
- Label all controls clearly
- Announce playback state changes
- Provide hints for gestures

### Reduce Motion
- Replace slide transitions with crossfade
- Keep Ken Burns but reduce motion intensity
- Respect `UIAccessibility.isReduceMotionEnabled`

### Dynamic Type
- Controls scale with user preferences
- Loading messages use system fonts

---

## Scalability Foundation

### Future Extensions (Not Phase 1)

**Phase 2**:
- Progressive loading (segment-based compositions)
- Background prefetch service
- Thumbnail generation

**Phase 3**:
- 3D transitions (Metal renderer)
- Playback speed control
- Advanced seeking features

**Architecture Support**:
- Protocol-based design (easy to add renderers)
- Clear separation of concerns
- Extensible without breaking existing code

---

## Implementation Checklist

### Phase 1 Components (From Scratch):
- [ ] `MediaAssetResolver` (actor)
  - Photos/iCloud resolution
  - Image encoding
  - Parallel loading
  - Error handling
  
- [ ] `CompositionAssembler` (struct)
  - Timeline calculation
  - Track insertion
  - Transition instructions
  - Audio mix
  
- [ ] `PlaybackEngine` (@MainActor ObservableObject)
  - AVPlayer management
  - State management
  - Observers
  - Seek functionality
  
- [ ] `TapePlayerController` (actor)
  - Orchestration
  - Error recovery
  - Progress tracking
  
- [ ] `TapePlayerView` (SwiftUI)
  - UI layout
  - State binding
  - Controls
  - Loading/error states

### Shared Utilities:
- [ ] `TransitionSequenceGenerator` (deterministic RNG)
- [ ] `SeededRNG` (linear congruential generator)
- [ ] Error types and messages

**Total Estimated Lines**: ~800-1000 (clean, well-documented, bulletproof)

---

## Key Design Decisions

### Why Actor for Asset Resolver?
- Thread-safe asset loading
- Prevents race conditions
- Swift concurrency best practice

### Why Actor for Controller?
- Thread-safe orchestration
- Clean async API
- Prevents concurrent preparations

### Why MainActor for Engine?
- AVPlayer must be on main thread
- UI updates must be on main thread
- ObservableObject needs main actor for @Published

### Why Single Composition?
- Simple and reliable
- No mid-playback swaps
- No timeline preservation complexity
- Fast enough for Phase 1 scope (< 30 clips)

### Why Parallel Loading?
- Fastest possible startup
- Uses TaskGroup (native, efficient)
- Independent timeouts per clip
- No blocking on slow clips

---

## Success Metrics

### Functional
- ✅ All transition types work seamlessly
- ✅ No playback jumping or glitches
- ✅ Smooth audio transitions
- ✅ Accurate seeking
- ✅ Clip boundary detection

### Performance
- ✅ TTFMP ≤ 3.0s p95
- ✅ Stall rate ≤ 1 per 5 minutes
- ✅ Memory ≤ 400MB peak
- ✅ 60fps playback on capable devices

### Reliability
- ✅ Handles all error scenarios gracefully
- ✅ Never crashes
- ✅ Recovers from network issues
- ✅ Works offline (local assets)

### User Experience
- ✅ Loading state clearly indicated
- ✅ Error messages are helpful
- ✅ Controls are responsive
- ✅ Full-screen immersive experience

---

**Document Version**: 1.0  
**Created**: Complete rebuild from scratch design  
**Status**: Ready for implementation  
**Principle**: Zero recycling, bulletproof logic, maximum performance

