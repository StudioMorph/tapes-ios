# Tape Player Complete Rebuild Plan
## Memories-Level Experience with Hybrid Loading Strategy

---

## Executive Summary

**Goal**: Build a production-ready, scalable, extensible tape player that delivers a "Memories"-level smooth experience with seamless transitions, fast loading using hybrid strategy (parallel for fast assets, sequential with overlap for slow assets), and future-ready architecture.

**Architecture Principles**:
- **Native APIs First**: Use AVFoundation, AVKit, Swift Concurrency directly
- **Hybrid Loading Strategy**: Optimize based on asset source type (local fast, Photos/iCloud sequential)
- **Time-Based Window**: Load as much as possible in 10-15 seconds, then start playback
- **Progressive Delivery**: Each phase produces a functional, testable player
- **Skip Behavior**: Skip assets not ready when playback reaches them (seamless UX)
- **iOS Best Practices**: Follow HIG, use native components, SwiftUI patterns

---

## Hybrid Loading Strategy (Core Innovation)

### Asset Source Performance Characteristics

1. **Local Files** (`localURL`): <100ms - Essentially instant
2. **Photos Library (Local)**: <500ms - Fast
3. **Photos Library (iCloud)**: 1-10s+ - Slow, variable
4. **Image Encoding**: 1-3s - CPU-bound

### Three-Tier Loading Approach

#### 1. Fast Queue (Parallel)
- **Source**: Local files (`localURL`)
- **Strategy**: Load ALL in parallel immediately
- **Why**: Instant load time, won't overwhelm system
- **Result**: Ready in <200ms total

#### 2. Sequential Priority Queue (Photos/iCloud)
- **Source**: Photos assets (`assetLocalId`)
- **Strategy**: Sequential loading with overlap
- **Pattern**: Start next clip when current is ~50% loaded or after 1-2s delay
- **Why**: 
  - Unknown if local or iCloud (can't predict speed)
  - Photos framework works best with 2-4 concurrent requests
  - Sequential with overlap maximizes throughput without overwhelming
- **Result**: ~5-7 clips ready in 15s window (depends on local vs iCloud mix)

#### 3. CPU Queue (Limited Parallel)
- **Source**: Image encodings (Ken Burns)
- **Strategy**: Max 2 concurrent encodings
- **Why**: CPU-intensive, system can handle 2-3 reasonably
- **Result**: ~2-3 images encoded in 15s window

### Time Window Implementation

**Window Duration**: 10-15 seconds (configurable)

**Flow**:
```
Time 0s:
  - Start all local files in parallel (fast queue)
  - Start Photos asset 1 (sequential queue)
  - Start image encoding 1 (CPU queue, if any)

Time 0.2s:
  - All local files ready ✓

Time 2s:
  - Photos asset 1 at ~50% → Start Photos asset 2
  - Image encoding 1 completes → Start image encoding 2 (if any)

Time 5s:
  - Photos asset 1 completes, asset 2 at ~50% → Start Photos asset 3
  - Image encoding 2 completes (if any)

Time 15s:
  - Window expires → Build composition with ready assets
  - Start playback immediately
  - Continue loading remaining assets in background
  - Skip assets not ready when playback reaches them
```

### Skip Behavior

**When Playback Reaches Unready Asset**:
- Skip immediately to next ready clip
- Continue loading skipped clip in background
- User never notices (seamless)
- Log skip for debugging (optional toast notification)

---

## Core Architecture

### Phase 1: Hybrid Loading Foundation

#### 1. HybridAssetLoader (New)
**Purpose**: Implement three-tier loading strategy

**Responsibilities**:
- Detect asset source type (local vs Photos)
- Route to appropriate queue (fast/sequential/CPU)
- Implement sequential overlap pattern
- Track loading progress
- Return ready assets after time window

**API**:
```swift
actor HybridAssetLoader {
    let windowDuration: TimeInterval = 15.0
    let overlapDelay: TimeInterval = 1.5 // Start next after 1.5s or 50% progress
    
    func loadWindow(clips: [Clip]) async -> WindowResult
    
    struct WindowResult {
        let readyAssets: [ResolvedAsset] // Ready by end of window
        let loadingAssets: [LoadingAsset] // Still loading
        let skippedAssets: [SkippedAsset] // Timed out/failed
    }
}
```

**Implementation Pattern**:
```swift
func loadWindow(clips: [Clip]) async -> WindowResult {
    let deadline = Date().addingTimeInterval(windowDuration)
    
    // Fast queue: All local files in parallel
    let localClips = clips.filter { $0.localURL != nil }
    let fastResults = await withTaskGroup { group in
        for clip in localClips {
            group.addTask { await resolveLocal(clip) }
        }
        // Collect all
    }
    
    // Sequential queue: Photos assets with overlap
    let photosClips = clips.filter { $0.assetLocalId != nil }
    var sequentialResults: [ResolvedAsset?] = []
    for (index, clip) in photosClips.enumerated() {
        if Date() >= deadline { break }
        
        // Start loading current clip
        let currentTask = Task { await resolvePhotos(clip) }
        
        // If not first clip, wait for overlap delay before starting next
        if index > 0 {
            try? await Task.sleep(nanoseconds: UInt64(overlapDelay * 1_000_000_000))
        }
        
        let result = await currentTask.value
        sequentialResults.append(result)
    }
    
    // CPU queue: Image encodings (max 2 concurrent)
    let imageClips = clips.filter { $0.clipType == .image }
    // ... implement with semaphore limit of 2
    
    return WindowResult(readyAssets: [...], loadingAssets: [...], skippedAssets: [...])
}
```

#### 2. Enhanced TapeCompositionBuilder
**Purpose**: Build composition with ready assets, handle skip behavior

**Enhancements**:
- Accept partial asset list (some may be skipped)
- Build composition with gaps for skipped clips
- Timeline calculation accounts for skipped clips
- Transitions only between consecutive ready clips

**Skip Handling**:
```swift
func buildComposition(
    tape: Tape,
    assets: [ResolvedAsset?] // nil = skipped
) throws -> PlayerComposition {
    // Filter out nil (skipped)
    let readyAssets = assets.compactMap { $0 }
    
    // Build timeline with only ready assets
    // Calculate transitions only between consecutive ready assets
    // Timeline accounts for skipped clips (no gaps in playback time)
}
```

#### 3. PlaybackEngine
**Purpose**: Own AVPlayer, manage playback state

**Responsibilities**:
- Install composition from builder
- Track current clip index
- Handle skip behavior (if asset becomes ready during playback)
- State management (@Published properties)
- Observers (time, end, stall, interruption)

**Skip Integration**:
- When playback reaches skipped clip → jump to next ready clip
- Optional: If skipped clip loads during playback → can extend composition forward (if not at end)

#### 4. TapePlayerView (SwiftUI)
**Purpose**: Full-screen player UI following HIG

**Implementation**:
- Full-screen black background (HIG immersive experience)
- `VideoPlayer` overlay (native component)
- Loading overlay (glass effect, "Loading tape...")
- Controls overlay (tap to reveal, auto-hide after 3s)
- AirPlay support (AVRoutePickerView, native component)
- Accessibility (VoiceOver, Reduce Motion)

---

## Phase 2: Scalability + Progressive Extension

**Goal**: Handle large tapes, extend composition during playback

### Enhancements

**1. Composition Extension**
- As more assets load during playback, extend composition forward
- Only works if user hasn't reached end yet
- Seamless extension (no playback interruption)

**2. BackgroundAssetService**
- Continue loading remaining assets in background
- Priority: clips needed soonest first
- Network-aware throttling

**3. Strategy Pattern**
- `SingleCompositionStrategy` (Phase 1)
- `ExtendableCompositionStrategy` (Phase 2)
- `QueueCompositionStrategy` (for 50+ clips)

---

## Phase 3: Advanced Features & 3D Transitions

**Goal**: 3D transitions, playback speed, advanced controls

### Components

**1. TransitionRenderer Protocol**
- `BasicTransitionRenderer` (2D, current)
- `MetalTransitionRenderer` (3D, Phase 3)

**2. Playback Speed Control**
- Variable speed (0.5x, 1x, 1.5x, 2x)
- Smooth transitions

**3. Advanced Controls**
- Thumbnail scrubbing
- Frame-by-frame seeking

---

## iOS Best Practices & HIG Compliance

### Native Components
- **VideoPlayer**: Native SwiftUI component (Phase 1)
- **AVRoutePickerView**: Native AirPlay button (Phase 1)
- **AVPlayer**: Native playback engine (Phase 1)
- **PHImageManager**: Native Photos access (Phase 1)

### Swift Concurrency
- **async/await**: All asset loading (Phase 1)
- **TaskGroup**: Parallel local file loading (Phase 1)
- **Actor**: Thread-safe asset loader (Phase 1)
- **@MainActor**: UI updates (Phase 1)

### HIG Compliance
- **Full-Screen Immersive**: Black background, video fills screen
- **Minimal UI**: Controls auto-hide, tap to reveal
- **Loading States**: Clear "Loading tape..." indicator
- **Error Handling**: User-friendly messages with recovery options
- **Accessibility**: VoiceOver support, Reduce Motion respected

### Performance Best Practices
- **Memory Management**: Release AVAssets after composition built
- **Background Tasks**: Proper background task handling
- **Energy Efficiency**: Throttle operations appropriately
- **Network Awareness**: Respect cellular vs Wi-Fi

---

## Performance Targets

### Phase 1 (Hybrid Loading)
- **TTFMP**: ≤ 2.0s p95 (local files instant, Photos 15s window)
- **Stall Rate**: ≤ 1 stall per 5 minutes p95
- **Skip Rate**: < 5% of clips (depends on network)
- **Memory**: ≤ 400MB peak
- **Local Files**: Ready in <200ms
- **Photos Assets**: ~5-7 ready in 15s window

### Phase 2
- **TTFMP**: ≤ 500ms p95 (progressive extension)
- **Large Tape Support**: 100+ clips
- **Memory**: ≤ 600MB peak
- **Prefetch Hit Rate**: 90%

### Phase 3
- **3D Transitions**: 60fps on supported devices
- **Speed Control**: < 100ms latency

---

## Error Handling

### Phase 1
- **Local File Missing**: Skip immediately, log error
- **Photos Access Denied**: Clear error message, Settings link
- **iCloud Timeout**: Skip after window expires, continue in background
- **Encoding Failure**: Skip image clip, continue with video clips
- **Network Error**: Retry with exponential backoff (up to window duration)

### Skip Behavior
- **Graceful Degradation**: Always start playback with available assets
- **User Transparency**: Optional toast notification for skipped clips
- **Background Recovery**: Continue loading skipped clips in background
- **Timeline Integrity**: Playback continues smoothly, no gaps in time

---

## Testing Strategy

### Phase 1
- **TTFMP Measurement**: Local vs Photos vs iCloud scenarios
- **Skip Rate Testing**: Slow network, timeout scenarios
- **Memory Profiling**: Peak memory during loading and playback
- **Stall Rate**: 5-minute playback sessions
- **Transition Parity**: Visual comparison with export output

### Edge Cases
- **All Local**: Should load instantly (<200ms)
- **All iCloud**: Should start after 15s with whatever ready
- **Mixed**: Fast local files + slow iCloud (hybrid strategy)
- **Network Failure**: Should start with local assets, skip iCloud
- **Photos Denied**: Clear error, no crash

---

## Migration Path

### Phase 1 → Phase 2
- Add composition extension capability
- Add background loading service
- No breaking changes to engine API
- Feature flag: `playbackEngineV2Phase2`

### Phase 2 → Phase 3
- Add transition renderer protocol
- Add Metal renderer
- Backward compatible
- Feature flag: `playbackEngineV2Phase3`

---

## Key Design Decisions

### Why Hybrid Loading?
- **Optimizes for reality**: Local files are instant, Photos are variable
- **Best of both worlds**: Fast parallel for fast assets, careful sequential for slow
- **System-friendly**: Doesn't overwhelm Photos framework or network
- **Predictable**: Time window ensures consistent startup experience

### Why Time Window?
- **Adapts to content**: Works regardless of clip durations
- **Predictable buffer**: Always ensures ~10-15s of ready content
- **Fast startup**: User sees playback in 15s max (vs waiting for all assets)
- **Progressive**: Can extend composition as more assets load

### Why Skip Behavior?
- **Never blocks**: Playback always starts
- **Seamless UX**: User doesn't notice skipped clips
- **Recovery**: Skipped clips continue loading in background
- **Resilient**: Handles network failures gracefully

### Why Native APIs?
- **Performance**: Apple's frameworks are optimized
- **Reliability**: Less custom code = fewer bugs
- **Maintenance**: Easier to maintain with standard patterns
- **Future-proof**: Updates to iOS benefit automatically

---

**Document Version**: 3.0 (Hybrid Loading Strategy)  
**Last Updated**: After deep analysis of asset source performance  
**Status**: Ready for Phase 1 implementation
