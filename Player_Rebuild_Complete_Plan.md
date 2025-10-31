# Tape Player Complete Rebuild Plan
## Memories-Level Experience with Full Scalability & Extensibility

---

## Executive Summary

**Goal**: Build a production-ready, scalable, extensible tape player that delivers a "Memories"-level smooth experience with seamless transitions, fast loading, and future-ready architecture for 3D transitions and advanced features.

**Architecture Principles**:
- **Native APIs First**: Use AVFoundation, AVKit, Swift Concurrency directly
- **Leverage Existing Code**: `TapeCompositionBuilder` already handles parallel loading and composition building
- **Progressive Delivery**: Each phase produces a functional, testable player
- **Scalability Built-In**: Simple foundation that's easy to extend
- **Performance & Reliability**: Fast startup, smooth playback, no jumping

---

## Key Discovery

**`TapeCompositionBuilder` already does everything Phase 1 needs:**
- ✅ Parallel asset loading using `TaskGroup` (Apple's native way)
- ✅ Handles Photos/iCloud assets automatically
- ✅ Builds `AVMutableComposition` with transitions
- ✅ Returns ready-to-play `PlayerComposition`

**Phase 1 should be simple:** Just call the builder directly. No need for custom AssetLoader, BackgroundAssetService, or ClipPrefetcher.

---

## Core Architecture (Updated Based on Research)

### Phase 1: Simple Foundation

**Core Principle**: Use existing `TapeCompositionBuilder` directly. No custom orchestration layer needed.

#### 1. SimplePlayerEngine (~100 lines)
**Purpose**: Own AVPlayer, manage playback state

**Responsibilities**:
- Own single AVPlayer instance
- Call `builder.buildPlayerItem(for: tape)` directly
- Install/remove observers (time, end, stall)
- Expose @Published state: `isPlaying`, `currentTime`, `currentClipIndex`, `isBuffering`, `isFinished`, `error`
- Handle playback interruptions (phone calls, backgrounding)

**API**:
```swift
@MainActor
class SimplePlayerEngine: ObservableObject {
    @Published var isBuffering = false
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var currentClipIndex: Int = 0
    @Published var error: String?
    
    private(set) var player: AVPlayer?
    private let builder = TapeCompositionBuilder()
    
    func prepare(tape: Tape) async
    func play()
    func pause()
    func seek(to seconds: Double, autoplay: Bool)
    func seekToClip(index: Int, autoplay: Bool)
    func teardown()
}
```

**Implementation Notes**:
- Calls `builder.buildPlayerItem(for: tape)` which:
  - Uses `TaskGroup` to load ALL clips in parallel
  - Handles Photos/iCloud automatically
  - Builds single `AVMutableComposition`
  - Returns `PlayerComposition`
- No coordinators, no prefetchers, no complex orchestration
- ~100 lines total

#### 2. TapeCompositionBuilder (Already Exists ✅)
**Purpose**: Load assets in parallel, build composition

**What it already does**:
- Parallel loading using `TaskGroup`:
  ```swift
  func loadAssets(for clips: [Clip], startIndex: Int) async throws -> [ClipAssetContext] {
      try await withThrowingTaskGroup(of: ClipAssetContext.self) { group in
          for (offset, clip) in clips.enumerated() {
              group.addTask {
                  // Each clip loads in parallel
                  try await resolveAsset(for: clip)
                  // ... create context
              }
          }
          // Collect all results
      }
  }
  ```
- Single composition building:
  ```swift
  func buildPlayerItem(for tape: Tape) async throws -> PlayerComposition {
      let contexts = try await loadAssets(for: tape.clips, startIndex: 0)
      let timeline = makeTimeline(for: tape, contexts: contexts)
      return try buildPlayerComposition(for: tape, timeline: timeline)
  }
  ```
- Handles Photos/iCloud via `PHImageManager`
- Handles transitions via `AVVideoComposition`
- Handles image-to-video encoding for Ken Burns

**Conclusion**: Use builder directly. No wrapper needed.

#### 3. PlayerView (SwiftUI, Minimal Changes)
**Purpose**: Thin UI layer that delegates to engine

**Implementation**:
```swift
struct TapePlayerView: View {
    @StateObject private var engine = SimplePlayerEngine()
    let tape: Tape
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = engine.player {
                VideoPlayer(player: player).disabled(true)
            }
            
            if engine.isBuffering {
                PlayerLoadingOverlay(isLoading: true, loadError: engine.error)
            }
            
            if showingControls {
                // Controls
            }
        }
        .onAppear {
            if FeatureFlags.playbackEngineV2Phase1 {
                Task { await engine.prepare(tape: tape) }
            }
        }
    }
}
```

**Changes**: ~20 lines of updates to existing view

---

## The Flow (Simple)

```
1. User taps play
   ↓
2. TapePlayerView.onAppear
   ↓
3. engine.prepare(tape:)
   - Set isBuffering = true immediately (shows loading overlay)
   ↓
4. builder.buildPlayerItem(for: tape)
   - Internally uses TaskGroup to load ALL clips in parallel
   - Each clip resolves concurrently (Photos/iCloud handled automatically)
   - If any clip fails/times out, builder handles it gracefully
   - Once all loaded, builds single AVMutableComposition with transitions
   - Returns PlayerComposition
   ↓
5. engine.install(composition)
   - Creates AVPlayer
   - Sets playerItem
   - Installs observers (time, end, stall)
   - Auto-plays
   - Set isBuffering = false (hides loading overlay)
   ↓
6. Playback starts smoothly with all clips
   - Single composition = no jumping
   - All clips ready = no stalling
   - Transitions work seamlessly
```

**Total complexity**: ~120 lines of new code

---

## Phase 2: Scalability + Performance Optimization
**Goal**: Handle large tapes efficiently, memory-conscious, network-adaptive

**Deliverable**: Production-ready player for tapes of any size (50+ clips)

### New Components

**1. CompositionStrategy Protocol** (New)
- `protocol CompositionStrategy`
- `SingleCompositionStrategy` (Phase 1 behavior, refactored)
- `SegmentCompositionStrategy` (chunks of 10-15 clips)
- `QueueCompositionStrategy` (AVQueuePlayer for 50+ clips)
- Strategy selection based on clip count and device capabilities

**2. Progressive Loading Service** (New)
- Background prefetch for upcoming clips
- Priority queue (current → next → next+1 → rest)
- Network-aware (Wi-Fi vs cellular)
- Memory-conscious (pause on memory warnings)

**3. BackgroundAssetService** (New)
- Persistent background queue for iCloud assets
- BGProcessingRequest for background execution
- Bandwidth estimation
- Network adaptation

**4. ThumbnailGenerator** (New)
- Generate thumbnails for scrubbing UI
- Cache on disk (keyed by clip ID + timestamp)
- Lazy loading: generate on-demand if not cached

**5. Advanced Prefetch** (Enhancement)
- Look-ahead window management
- Device capability adaptation
- Memory pressure handling

---

## Phase 3: Advanced Features & 3D Transitions
**Goal**: 3D transitions, playback speed control, advanced customization

**Deliverable**: Production-ready player with 3D transitions and advanced controls

### New Components

**1. TransitionRenderer Protocol** (New)
- Abstract transition rendering
- `BasicTransitionRenderer` (2D transitions)
- `MetalTransitionRenderer` (3D transitions via Metal)
- Pluggable renderers

**2. Playback Speed Control** (Enhancement)
- Variable speed (0.5x, 1x, 1.5x, 2x)
- Speed change without seeking
- Smooth transitions

**3. Advanced Controls** (UI)
- Thumbnail scrubbing with preview
- Frame-by-frame seeking
- Playback speed UI

---

## Scalability Strategy

### Small Tapes (< 30 clips)
- **Phase 1**: Single composition (current approach)
- All clips in one `AVMutableComposition`
- Fast, simple, reliable

### Medium Tapes (30-50 clips)
- **Phase 2**: Segment-based strategy
- Chunks of 10-15 clips per composition
- Swap compositions at safe boundaries
- Timeline preservation

### Large Tapes (50+ clips)
- **Phase 2**: Queue-based strategy
- `AVQueuePlayer` with multiple items
- Progressive loading
- Memory-conscious

---

## Performance Targets

### Phase 1
- **TTFMP**: ≤ 2.0s p95 (all clips load in parallel)
- **Stall Rate**: ≤ 1 stall per 5 minutes p95
- **Transition Smoothness**: No visible hiccups
- **Memory**: ≤ 400MB peak

### Phase 2
- **TTFMP**: ≤ 500ms p95 (progressive loading)
- **Large Tape Support**: 100+ clips without memory issues
- **Background Prefetch**: 90% hit rate for iCloud assets

### Phase 3
- **3D Transition Performance**: 60fps on supported devices
- **Speed Control Latency**: < 100ms

---

## Error Handling

### Phase 1
- Per-clip errors handled by builder
- Timeout/retry built into builder's asset loading
- Graceful degradation (skip failed clips if needed)

### Phase 2
- Advanced error recovery
- Network retry strategies
- User-friendly error messages

---

## Testing Strategy

### Phase 1
- TTFMP validation (local and iCloud)
- Stall rate measurement
- Memory usage profiling
- Error scenario testing

### Phase 2
- Large tape testing (50+ clips)
- Network condition simulation
- Memory pressure testing
- Background execution testing

### Phase 3
- 3D transition performance testing
- Device capability testing
- Playback speed accuracy

---

## Migration Path

### Phase 1 → Phase 2
- Wrap engine in coordinator (if needed)
- Add strategy protocol
- Add progressive loading service
- No breaking changes to engine API

### Phase 2 → Phase 3
- Add transition renderer protocol
- Add Metal renderer
- Extend builder with renderer injection
- Backward compatible

---

## Key Design Decisions

### Why Use Builder Directly (Phase 1)?
- **No duplication**: Builder already does parallel loading
- **Native APIs**: Uses `TaskGroup` (Apple's way)
- **Simple**: One call, get composition
- **Fast**: Parallel loading, build once
- **Reliable**: Single composition, no jumping

### Why No Coordinator in Phase 1?
- **Unnecessary complexity**: Builder already orchestrates loading
- **Over-engineering**: Simple direct call is sufficient
- **Easy to add later**: Can wrap in coordinator for Phase 2 if needed

### Why No BackgroundAssetService in Phase 1?
- **Builder's TaskGroup**: Already loads in parallel efficiently
- **Not needed**: Single composition doesn't need background prefetch
- **Phase 2 feature**: Add when we need progressive compositions

---

**Document Version**: 2.0 (Rewritten based on research)  
**Last Updated**: After clean architecture analysis  
**Status**: Ready for Phase 1 implementation
