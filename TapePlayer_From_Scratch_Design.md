# Tape Player - From Scratch Design
## Complete Rebuild with Hybrid Loading Strategy & iOS Best Practices

---

## Core Principle: Zero Recycling, Fresh Architecture

**What We Keep (Data Only)**:
- `Tape` model (data structure)
- `Clip` model (data structure)
- `TransitionType` enum (transition definitions)

**What We Build Fresh (No Recycling)**:
- Hybrid asset loading system (from scratch)
- Enhanced composition building with skip support (from scratch)
- Player engine (from scratch)
- State management (from scratch)
- Transition rendering (from scratch)
- UI layer (from scratch)

---

## Architecture Overview

### Design Goals
1. **Bulletproof Logic**: Comprehensive error handling, state validation, edge case coverage
2. **Performance**: Optimized memory usage, intelligent asset loading, smooth playback
3. **Seamless Transitions**: Transitions rendered perfectly between clips, no glitches
4. **Native APIs**: Use AVFoundation, AVKit, SwiftUI, Swift Concurrency directly
5. **HIG Compliance**: Follow iOS Human Interface Guidelines
6. **Scalability**: Foundation that supports future features (3D transitions, etc.)

---

## Hybrid Loading Architecture

### Asset Source Performance Characteristics

1. **Local Files** (`localURL`): <100ms - Essentially instant
2. **Photos Library (Local)**: <500ms - Fast
3. **Photos Library (iCloud)**: 1-10s+ - Slow, variable
4. **Image Encoding**: 1-3s - CPU-bound

### Three-Tier Loading Strategy

#### 1. Fast Queue (Parallel)
**Purpose**: Load local files instantly

**Implementation**:
```swift
// Load all local files in parallel
let localClips = clips.filter { $0.localURL != nil }
await withTaskGroup(of: ResolvedAsset.self) { group in
    for clip in localClips {
        group.addTask {
            try await resolveLocalFile(clip)
        }
    }
    // Collect all results
}
```

**Characteristics**:
- All clips start loading simultaneously
- Ready in <200ms total
- No system resource concerns (local file access is fast)

#### 2. Sequential Priority Queue (Overlap)
**Purpose**: Load Photos/iCloud assets efficiently

**Implementation**:
```swift
// Sequential with overlap
for (index, clip) in photosClips.enumerated() {
    if Date() >= deadline { break }
    
    // Start loading current clip
    let currentTask = Task { await resolvePhotos(clip) }
    
    // Overlap: Start next after delay (1.5s works well)
    if index > 0 {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    
    let result = await currentTask.value
}
```

**Characteristics**:
- One clip at a time (respects Photos framework limits)
- Overlap: Next clip starts before current finishes
- Adaptive: Works for both local Photos and iCloud
- ~5-7 clips ready in 15s window (depends on local vs iCloud mix)

**Why Sequential Overlap?**:
- Photos framework optimized for 2-4 concurrent requests
- Unknown if asset is local or iCloud until loading starts
- Overlap maximizes throughput without overwhelming framework
- System-friendly: Doesn't cause framework congestion

#### 3. CPU Queue (Limited Parallel)
**Purpose**: Encode images to video (Ken Burns)

**Implementation**:
```swift
// Max 2 concurrent encodings
let semaphore = DispatchSemaphore(value: 2)

for imageClip in imageClips {
    await semaphore.wait()
    Task {
        defer { semaphore.signal() }
        try await encodeImageToVideo(imageClip)
    }
}
```

**Characteristics**:
- Max 2 concurrent (CPU-intensive)
- ~2-3 images encoded in 15s window
- System-friendly: Doesn't overwhelm CPU

### Time Window Implementation

**Window Duration**: 10-15 seconds (configurable)

**Flow**:
```
Time 0s:
  - Start all local files in parallel
  - Start Photos asset 1
  - Start image encoding 1 (if any)

Time 0.2s:
  - All local files ready ✓

Time 1.5s:
  - Photos asset 1 at ~50% → Start Photos asset 2

Time 3s:
  - Photos asset 1 done, asset 2 at ~50% → Start Photos asset 3
  - Image encoding 1 done → Start image encoding 2 (if any)

Time 15s:
  - Window expires → Build composition with ready assets
  - Start playback immediately
  - Continue loading remaining assets in background
```

**Result**: ~5-7 Photos assets + all local files ready in 15s

---

## Component Architecture (From Scratch)

### 1. HybridAssetLoader
**Purpose**: Implement three-tier loading strategy with time window

**API**:
```swift
actor HybridAssetLoader {
    let windowDuration: TimeInterval = 15.0
    let overlapDelay: TimeInterval = 1.5
    
    func loadWindow(clips: [Clip]) async -> WindowResult
    
    struct WindowResult {
        let readyAssets: [(Int, ResolvedAsset)] // (clipIndex, asset)
        let loadingAssets: [Int] // Clip indices still loading
        let skippedAssets: [SkippedAsset] // Timed out/failed
    }
    
    struct SkippedAsset {
        let clipIndex: Int
        let reason: SkipReason
    }
    
    enum SkipReason {
        case timeout
        case error
        case cancelled
    }
}
```

**Implementation**:
- Fast queue: All local files in parallel (TaskGroup)
- Sequential queue: Photos assets with overlap pattern
- CPU queue: Image encodings with semaphore limit (max 2)
- Progress tracking
- Timeout handling
- Error classification

**Error Handling**:
- Network timeouts: Skip after window expires
- Photos denied: Clear error, skip immediately
- Missing asset: Skip immediately
- Encoding failure: Skip image clip, continue

### 2. Enhanced CompositionAssembler
**Purpose**: Build composition with ready assets, handle skipped clips

**Enhancements**:
- Accept partial asset list (some clips may be skipped)
- Build timeline accounting for skipped clips
- Transitions only between consecutive ready clips
- Skip markers in timeline (for potential extension later)

**API**:
```swift
struct CompositionAssembler {
    func assembleComposition(
        tape: Tape,
        readyAssets: [(Int, ResolvedAsset)], // Only ready assets
        skippedIndices: Set<Int> // Which clips were skipped
    ) throws -> AssembledComposition {
        // Build timeline with only ready assets
        // Calculate transitions only between consecutive ready clips
        // Timeline accounts for skipped clips (no gaps in playback time)
    }
}
```

**Timeline Calculation**:
```
Ready assets: [0, 1, 3, 5, 7] (skipped 2, 4, 6)
Timeline:
  - Clip 0: 0s → 5s
  - Clip 1: 5s → 10s (transition from clip 0)
  - [Skip clip 2]
  - Clip 3: 10s → 15s (hard cut, no transition from clip 1)
  - [Skip clip 4]
  - Clip 5: 15s → 20s (hard cut, no transition)
  - [Skip clip 6]
  - Clip 7: 20s → 25s (hard cut, no transition)
```

**Transition Rules**:
- Transitions only between consecutive ready clips
- If clip skipped → hard cut to next ready clip
- No transition duration in skipped gaps

### 3. PlaybackEngine
**Purpose**: Own AVPlayer, manage playback state and lifecycle

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
    
    private(set) var player: AVPlayer?
    private let skipHandler: SkipHandler
    
    func prepare(tape: Tape) async
    func play()
    func pause()
    func seek(to time: Double)
    func seekToClip(at index: Int)
    func teardown()
}
```

**Skip Integration**:
- `SkipHandler` tracks skipped clip indices
- Monitor playback position
- If reaches skipped clip → jump to next ready clip
- Optional toast notification for skipped clips

**State Management**:
- Single source of truth (@Published properties)
- Thread-safe updates (@MainActor)
- Clear state transitions (Loading → Ready → Playing → Finished)

**Observers**:
- Time observer: Update currentTime every 0.1s
- End observer: Detect playback completion
- Stall observer: Detect buffering state
- Interruption observer: Handle phone calls, backgrounding

### 4. SkipHandler
**Purpose**: Manage skip behavior during playback

**API**:
```swift
class SkipHandler {
    private let skippedIndices: Set<Int>
    private let readyIndices: Set<Int>
    
    func nextReadyClip(after index: Int) -> Int?
    func shouldSkip(clipIndex: Int) -> Bool
    func handleSkip(at index: Int, currentTime: CMTime) -> CMTime
}
```

**Behavior**:
- Track which clips are skipped
- Provide next ready clip index
- Calculate seek position when skipping
- Optional: Toast notification ("Skipped clip X")

### 5. TapePlayerView
**Purpose**: Full-screen SwiftUI player following HIG

**Implementation**:
```swift
struct TapePlayerView: View {
    @StateObject private var engine = PlaybackEngine()
    let tape: Tape
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // HIG: Immersive full-screen
            
            if let player = engine.player {
                VideoPlayer(player: player)
                    .disabled(true)
            }
            
            if engine.isBuffering {
                PlayerLoadingOverlay()
            }
            
            if showingControls {
                VStack {
                    PlayerHeader(onDismiss: onDismiss)
                    Spacer()
                    ControlsOverlay(engine: engine)
                }
            }
        }
        .onAppear {
            Task { await engine.prepare(tape: tape) }
        }
        .onDisappear {
            engine.teardown()
        }
    }
}
```

**HIG Compliance**:
- Full-screen black background (immersive experience)
- Video fills screen (native VideoPlayer)
- Controls auto-hide after 3s (standard pattern)
- Tap to reveal controls
- AirPlay button (AVRoutePickerView, native component)
- Accessibility support (VoiceOver, Reduce Motion)

---

## Skip Behavior Implementation

### When Playback Reaches Skipped Clip

**Detection**:
```swift
// In PlaybackEngine time observer
func updateCurrentClip() {
    let currentTime = player.currentTime()
    let currentClip = timeline.clipIndex(at: currentTime)
    
    if skipHandler.shouldSkip(clipIndex: currentClip) {
        // Skip to next ready clip
        if let nextReady = skipHandler.nextReadyClip(after: currentClip) {
            seekToClip(at: nextReady)
            // Optional: Show toast notification
        }
    }
}
```

**Seek Calculation**:
```swift
func seekToClip(at index: Int) {
    guard let startTime = timeline.startTime(for: index) else { return }
    player.seek(to: startTime)
    currentClipIndex = index
}
```

**User Experience**:
- Playback continues smoothly
- No stalling or waiting
- Optional toast: "Skipped clip X" (can be dismissed)
- Background loading continues for skipped clips

---

## iOS Best Practices & HIG Compliance

### Native Components Used

1. **VideoPlayer** (SwiftUI)
   - Native full-screen video playback
   - Automatic scaling and layout
   - Built-in gesture support

2. **AVRoutePickerView** (SwiftUI)
   - Native AirPlay/Casting picker
   - System-standard UI
   - Automatic device discovery

3. **AVPlayer** (AVFoundation)
   - Native playback engine
   - Automatic buffering management
   - System-level integration

4. **PHImageManager** (Photos)
   - Native Photos library access
   - Automatic iCloud handling
   - Network access management

### Swift Concurrency Patterns

1. **async/await**
   - All asset loading operations
   - Composition building
   - Non-blocking UI updates

2. **TaskGroup**
   - Parallel local file loading
   - Structured concurrency
   - Automatic error handling

3. **Actor**
   - Thread-safe asset loader
   - Prevents data races
   - Swift concurrency best practice

4. **@MainActor**
   - All UI updates
   - PlaybackEngine state management
   - Thread-safe property updates

### HIG Compliance

1. **Full-Screen Immersive**
   - Black background
   - Video fills screen
   - Minimal UI (controls auto-hide)

2. **Loading States**
   - Clear "Loading tape..." indicator
   - Progress indication (optional)
   - Error messages with recovery options

3. **Accessibility**
   - VoiceOver support (all controls labeled)
   - Reduce Motion support (slide transitions → crossfade)
   - Dynamic Type support (controls scale with text size)

4. **Error Handling**
   - User-friendly messages
   - Recovery options (retry, settings link)
   - Graceful degradation (skip failed assets)

### Performance Best Practices

1. **Memory Management**
   - Release AVAssets after composition built
   - Clean up temporary files (image encodings)
   - Monitor memory pressure

2. **Energy Efficiency**
   - Limit concurrent operations
   - Throttle background loading
   - Pause on memory warnings

3. **Network Awareness**
   - Respect cellular vs Wi-Fi
   - Throttle iCloud downloads on cellular
   - Background task management

---

## Performance Targets

### Time to First Frame Played (TTFMP)
- **Local files only**: ≤ 200ms p95
- **Photos (local)**: ≤ 2.0s p95
- **Mixed (local + iCloud)**: ≤ 15.0s p95 (window duration)
- **All iCloud**: ≤ 15.0s p95 (window duration)

### Skip Rate
- **Good network**: < 2% of clips
- **Slow network**: < 10% of clips
- **No network (iCloud)**: Skip all iCloud, play local only

### Stall Rate
- **Local files**: Zero stalls
- **Photos (local)**: ≤ 1 stall per 5 minutes p95
- **Mixed**: ≤ 1 stall per 5 minutes p95

### Memory Usage
- **Small tapes (< 30 clips)**: ≤ 300MB peak
- **Medium tapes (30-50 clips)**: ≤ 400MB peak
- **Large tapes (50+ clips)**: ≤ 600MB peak (Phase 2)

---

## Error Handling

### Error Classification

```swift
enum PlaybackError: Error, LocalizedError {
    case noClips
    case photosAccessDenied
    case assetMissing(clipIndex: Int)
    case encodingFailed(clipIndex: Int)
    case compositionFailed(String)
    case networkTimeout(clipIndex: Int)
    case noReadyClips // All clips failed/skipped
    
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
        case .noReadyClips:
            return "Unable to load any clips for this tape."
        }
    }
}
```

### Recovery Strategies

1. **Network Timeout**
   - Skip clip after window expires
   - Continue loading in background
   - May become ready during playback

2. **Asset Missing**
   - Skip immediately
   - Log for debugging
   - Continue with remaining clips

3. **Encoding Failure**
   - Skip image clip
   - Continue with video clips
   - Optional: Retry in background

4. **Photos Denied**
   - Clear error message
   - Link to Settings
   - Skip all Photos assets, try local files

5. **All Clips Failed**
   - Show error message
   - Provide retry option
   - Option to dismiss

---

## Testing Strategy

### Unit Tests
- HybridAssetLoader: Fast/sequential/CPU queue behavior
- CompositionAssembler: Skip handling, timeline calculation
- SkipHandler: Next ready clip calculation
- Error handling: All error paths

### Integration Tests
- End-to-end playback (load → build → play → skip)
- Skip behavior during playback
- Composition building with skipped clips
- Transition handling with gaps

### Performance Tests
- TTFMP measurement (local/Photos/mixed scenarios)
- Skip rate measurement (various network conditions)
- Stall rate measurement (5-minute sessions)
- Memory profiling (peak usage)

### Manual Testing
- Local-only tapes
- iCloud-only tapes
- Mixed tapes
- Image-only tapes
- Various transition types
- Error scenarios (Photos denied, network offline)
- Skip behavior (slow network simulation)
- Interruption handling (phone calls)

---

## Accessibility

### VoiceOver
- All controls labeled clearly
- State announcements ("Playing", "Paused", "Clip 3 of 12")
- Progress bar announces current time
- Error messages read aloud

### Reduce Motion
- Slide transitions → crossfade
- Ken Burns effect → static image
- Respect `UIAccessibility.isReduceMotionEnabled`

### Dynamic Type
- Controls scale with text size preference
- Loading messages use system fonts
- Readable at all text sizes

---

## Scalability Foundation

### Phase 2 Extensions
- Progressive composition extension
- Background prefetch service
- Thumbnail generation
- Large tape strategies (queue-based)

### Phase 3 Extensions
- 3D transitions (Metal renderer)
- Playback speed control
- Advanced seeking features
- Custom transition effects

**Architecture Support**:
- Protocol-based design (easy to add renderers)
- Clear separation of concerns
- Extensible without breaking existing code

---

## Key Design Decisions

### Why Hybrid Loading?
- **Reality-based**: Local files instant, Photos variable
- **System-friendly**: Doesn't overwhelm Photos framework
- **Optimal resource usage**: Parallel where safe, sequential where needed
- **Fast startup**: Local files ready instantly, Photos in reasonable time

### Why Time Window?
- **Predictable buffer**: Always ensures ~10-15s of ready content
- **Fast startup**: User sees playback in 15s max
- **Adapts to content**: Works regardless of clip durations
- **Progressive**: Can extend as more assets load

### Why Skip Behavior?
- **Never blocks**: Playback always starts with available assets
- **Seamless UX**: User doesn't notice skipped clips
- **Resilient**: Handles network failures gracefully
- **Recovery**: Skipped clips continue loading in background

### Why Native APIs?
- **Performance**: Apple's frameworks are optimized
- **Reliability**: Less custom code = fewer bugs
- **Maintenance**: Easier to maintain with standard patterns
- **Future-proof**: iOS updates benefit automatically

### Why Sequential Overlap for Photos?
- **Unknown speed**: Can't predict local vs iCloud
- **Framework limits**: Photos optimized for 2-4 concurrent
- **Overlap maximizes throughput**: Next starts before current finishes
- **System-friendly**: Doesn't cause framework congestion

---

**Document Version**: 3.0 (Hybrid Loading Strategy)  
**Created**: Complete rebuild from scratch design  
**Status**: Ready for implementation  
**Principle**: Hybrid loading, bulletproof logic, maximum performance, HIG compliance
