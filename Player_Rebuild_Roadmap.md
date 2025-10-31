# Tape Player Rebuild Roadmap
## Phased Implementation with Hybrid Loading Strategy

---

## Overview

This roadmap divides the complete rebuild plan into **3 phases**. Each phase produces a **fully functional, testable player** that can be shipped independently. Architecture uses hybrid loading strategy (parallel for fast assets, sequential with overlap for slow assets) following iOS best practices and HIG.

**Key Principles**:
- **Hybrid Loading**: Optimize based on asset source (local fast, Photos/iCloud sequential)
- **Time-Based Window**: 10-15 second loading window, start playback with ready assets
- **Skip Behavior**: Skip assets not ready when playback reaches them (seamless UX)
- **Each phase is shippable**: You can stop at any phase and have a working player
- **Native APIs first**: Use Apple's frameworks directly (AVFoundation, AVKit, SwiftUI)
- **HIG compliant**: Follow iOS Human Interface Guidelines
- **Feature flag per phase**: Enable/disable phase features independently

---

## Phase 1: Hybrid Loading Foundation
**Goal**: Fast startup with hybrid loading strategy, smooth transitions, skip behavior

**Deliverable**: Production-ready player for small-to-medium tapes (up to ~30 clips) with 2D transitions and intelligent asset loading

### Core Innovation: Hybrid Loading Strategy

**Three-Tier Approach**:
1. **Fast Queue** (Parallel): Local files load instantly in parallel
2. **Sequential Queue** (Overlap): Photos/iCloud assets load sequentially with overlap
3. **CPU Queue** (Limited Parallel): Image encodings max 2 concurrent

**Time Window**: 10-15 seconds
- Load as many assets as possible during window
- Start playback with ready assets after window expires
- Skip assets not ready when playback reaches them
- Continue loading remaining assets in background

### Components

**1. HybridAssetLoader** (~300 lines)
- ✅ Actor-based (thread-safe)
- ✅ Three-tier queue management
- ✅ Sequential overlap pattern (start next at ~50% or 1.5s delay)
- ✅ Time window tracking
- ✅ Progress reporting
- ✅ Timeout handling
- ✅ Returns WindowResult (ready/loading/skipped assets)

**2. Enhanced TapeCompositionBuilder** (Modify Existing)
- ✅ Accept partial asset list (nil = skipped)
- ✅ Build composition with only ready assets
- ✅ Timeline accounts for skipped clips (no gaps in playback time)
- ✅ Transitions only between consecutive ready clips
- ✅ Skip marker support in timeline

**3. PlaybackEngine** (~150 lines)
- ✅ @MainActor ObservableObject
- ✅ Own AVPlayer instance
- ✅ @Published state: isPlaying, currentTime, currentClipIndex, isBuffering, error
- ✅ Install composition from builder
- ✅ Skip behavior integration (jump to next ready clip if current skipped)
- ✅ Time/end/stall observers
- ✅ Basic interruption handling (phone calls, backgrounding)
- ✅ API: prepare, play, pause, seek, seekToClip, teardown

**4. TapePlayerView** (SwiftUI, ~100 lines updates)
- ✅ Full-screen black background (HIG immersive)
- ✅ VideoPlayer overlay (native SwiftUI component)
- ✅ Glass "Loading Tape" overlay (when engine.isBuffering)
- ✅ Controls: Play/Pause, Previous/Next, Progress scrubber, Dismiss
- ✅ Auto-hide controls after 3s (HIG pattern)
- ✅ Tap to reveal controls
- ✅ AirPlay button (AVRoutePickerView, native component)
- ✅ Accessibility: VoiceOver labels, Reduce Motion support

**5. SkipHandler** (~50 lines)
- ✅ Track which clips are skipped
- ✅ Provide next ready clip index
- ✅ Optional: Toast notification for skipped clips
- ✅ Background recovery tracking

### Implementation Flow

```
1. User taps play
   ↓
2. TapePlayerView.onAppear
   ↓
3. engine.prepare(tape:)
   - Set isBuffering = true (immediate - shows loading)
   ↓
4. HybridAssetLoader.loadWindow(clips:)
   - Fast queue: Load all local files in parallel
   - Sequential queue: Load Photos assets with overlap
   - CPU queue: Encode images (max 2 concurrent)
   - Track progress, handle timeouts
   - After 15s window: Return WindowResult
   ↓
5. builder.buildPlayerItem(for: tape, assets: windowResult.readyAssets)
   - Build composition with ready assets only
   - Handle skipped assets (nil markers)
   - Calculate timeline (no gaps in playback time)
   - Transitions only between consecutive ready assets
   ↓
6. engine.install(composition)
   - Create AVPlayer
   - Set playerItem
   - Install observers
   - Auto-play
   - Set isBuffering = false (hides loading)
   ↓
7. Playback starts smoothly
   - Single composition = no jumping
   - Ready assets = no stalling
   - SkipHandler monitors playback position
   - If playback reaches skipped asset → jump to next ready
   ↓
8. Background loading continues
   - Remaining assets continue loading
   - If asset becomes ready → log for future use
   - (Extension to composition deferred to Phase 2)
```

### Hybrid Loading Details

**Fast Queue Implementation**:
```swift
// All local files in parallel
let localClips = clips.filter { $0.localURL != nil }
await withTaskGroup(of: ResolvedAsset.self) { group in
    for clip in localClips {
        group.addTask { await resolveLocalFile(clip) }
    }
    // All ready in <200ms
}
```

**Sequential Queue Implementation**:
```swift
// Photos assets with overlap
for (index, clip) in photosClips.enumerated() {
    if Date() >= deadline { break }
    
    let currentTask = Task { await resolvePhotos(clip) }
    
    // Overlap: Start next after 1.5s or when current ~50% done
    if index > 0 {
        // Simple: Fixed delay (1.5s works well)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    
    let result = await currentTask.value
}
```

**CPU Queue Implementation**:
```swift
// Image encodings with semaphore limit
let semaphore = DispatchSemaphore(value: 2) // Max 2 concurrent

for imageClip in imageClips {
    await semaphore.wait()
    Task {
        defer { semaphore.signal() }
        await encodeImageToVideo(imageClip)
    }
}
```

### Acceptance Criteria

- ✅ **TTFMP**: ≤ 2.0s p95 (local files instant, Photos within 15s window)
- ✅ **Skip Rate**: < 5% of clips (depends on network/tape composition)
- ✅ **Stall Rate**: ≤ 1 stall per 5 minutes p95
- ✅ **Transition Smoothness**: No visible hiccups at boundaries
- ✅ **Visual Parity**: Transitions match export output
- ✅ **No Jumping**: Single composition = no mid-playback replacements
- ✅ **Skip Behavior**: Seamless skip when reaching unready asset
- ✅ **Basic Lifecycle**: Handles phone calls, app switching (pauses)
- ✅ **Accessibility**: VoiceOver works, Reduce Motion respected
- ✅ **Memory**: ≤ 400MB peak

### Feature Flag
- `playbackEngineV2Phase1`: Enable/disable Phase 1 features

### Testing Checklist
- [ ] TTFMP validation (local-only, Photos-only, mixed tapes)
- [ ] Skip behavior testing (slow network, timeout scenarios)
- [ ] Stall rate measurement (5-minute playback sessions)
- [ ] Transition visual parity vs export
- [ ] Memory usage (≤ 400MB peak)
- [ ] Error scenarios (Photos denied, timeout, missing asset)
- [ ] Interruption handling (phone call during playback)
- [ ] Large tape testing (30 clips)
- [ ] Edge cases (all local, all iCloud, all images)

### Estimated Timeline
- **Duration**: 1-2 weeks
- **Dependencies**: None (enhances existing builder)
- **Risk**: Low (straightforward pattern, proven approach)

---

## Phase 2: Scalability + Progressive Extension
**Goal**: Handle large tapes, extend composition during playback, background prefetch

**Deliverable**: Production-ready player for tapes of any size (50+ clips) with memory-conscious progressive extension

### New Components

**1. CompositionExtensionManager** (New)
- ✅ Extend composition forward as more assets load
- ✅ Seamless extension (no playback interruption)
- ✅ Only extend if user hasn't reached end
- ✅ Timeline preservation during extension

**2. BackgroundAssetService** (New)
- ✅ Continue loading remaining assets in background
- ✅ Priority queue (clips needed soonest first)
- ✅ Network-aware (Wi-Fi vs cellular throttling)
- ✅ Memory-conscious (pause on memory warnings)

**3. CompositionStrategy Protocol** (New)
- ✅ `SingleCompositionStrategy` (Phase 1 behavior, refactored)
- ✅ `ExtendableCompositionStrategy` (Phase 2 behavior)
- ✅ `QueueCompositionStrategy` (for 50+ clips, Phase 2 optional)

**4. ThumbnailGenerator** (New)
- ✅ Generate thumbnails for scrubbing UI
- ✅ Cache on disk (keyed by clip ID + timestamp)
- ✅ Lazy loading: generate on-demand if not cached

**5. PlaybackCoordinator** (New - If Needed)
- ✅ Orchestrate progressive extension
- ✅ Manage composition swapping (if using queue strategy)
- ✅ Timeline preservation during swaps

### Enhancements

**Progressive Extension**:
- As assets load in background, extend composition forward
- Only works if playback position < composition end
- Seamless: user doesn't notice extension happening
- Timeline continues smoothly

**Background Prefetch**:
- After window, continue loading remaining assets
- Prioritize: next needed clips first
- Network-aware: throttle on cellular
- Memory-aware: pause if memory pressure

### Acceptance Criteria

- ✅ **Large Tape Support**: 100+ clips without memory issues
- ✅ **TTFMP**: ≤ 500ms p95 (progressive extension reduces wait)
- ✅ **Extension Seamlessness**: No playback interruption when extending
- ✅ **Background Prefetch**: 90% hit rate for iCloud assets
- ✅ **Memory**: ≤ 600MB peak for large tapes
- ✅ **Network Adaptation**: Automatic throttling on cellular

### Feature Flag
- `playbackEngineV2Phase2`: Enable/disable Phase 2 features

### Estimated Timeline
- **Duration**: 2-3 weeks
- **Dependencies**: Phase 1 complete
- **Risk**: Medium (more complex, but Phase 1 provides foundation)

---

## Phase 3: Advanced Features & 3D Transitions
**Goal**: 3D transitions, playback speed control, advanced customization

**Deliverable**: Production-ready player with 3D transitions and advanced controls

### New Components

**1. TransitionRenderer Protocol** (New)
- ✅ `protocol TransitionRenderer`
- ✅ `BasicTransitionRenderer` (2D transitions, refactored from Phase 1)
- ✅ `MetalTransitionRenderer` (3D transitions via Metal)
- ✅ Pluggable renderers

**2. Playback Speed Control** (Enhancement)
- ✅ Variable speed (0.5x, 1x, 1.5x, 2x)
- ✅ Speed change without seeking
- ✅ Smooth transitions

**3. Advanced Controls** (UI)
- ✅ Thumbnail scrubbing with preview
- ✅ Frame-by-frame seeking
- ✅ Playback speed UI

### Acceptance Criteria

- ✅ **3D Transition Performance**: 60fps on supported devices
- ✅ **Speed Control Latency**: < 100ms
- ✅ **Device Compatibility**: Graceful fallback for unsupported devices

### Feature Flag
- `playbackEngineV2Phase3`: Enable/disable Phase 3 features

### Estimated Timeline
- **Duration**: 2-3 weeks
- **Dependencies**: Phase 1 complete (Phase 2 optional)
- **Risk**: Medium (Metal rendering complexity)

---

## Key Architectural Decisions

### Why Hybrid Loading?
1. **Reality-based**: Local files are instant, Photos are variable speed
2. **System-friendly**: Doesn't overwhelm Photos framework (2-4 concurrent optimal)
3. **Fast startup**: Local files ready instantly, Photos in 15s window
4. **Optimal resource usage**: Parallel where safe, sequential where needed

### Why Time Window?
1. **Adapts to content**: Works regardless of clip durations
2. **Predictable buffer**: Always ensures ~10-15s of ready content
3. **Fast startup**: User sees playback in 15s max
4. **Progressive**: Can extend composition as more assets load

### Why Skip Behavior?
1. **Never blocks**: Playback always starts with available assets
2. **Seamless UX**: User doesn't notice skipped clips
3. **Resilient**: Handles network failures gracefully
4. **Recovery**: Skipped clips continue loading in background

### Why Native APIs?
1. **Performance**: Apple's frameworks are optimized
2. **Reliability**: Less custom code = fewer bugs
3. **Maintenance**: Easier to maintain with standard patterns
4. **Future-proof**: iOS updates benefit automatically

### Why Sequential Overlap for Photos?
1. **Unknown speed**: Can't predict if local or iCloud until loading starts
2. **Photos framework limits**: 2-4 concurrent requests optimal
3. **Overlap maximizes throughput**: Next starts before current finishes
4. **System-friendly**: Doesn't overwhelm framework

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

## Success Metrics

### Phase 1
- TTFMP ≤ 2.0s p95
- Skip rate < 5%
- Stall rate ≤ 1 per 5 minutes p95
- Memory ≤ 400MB peak
- Zero playback jumping

### Phase 2
- TTFMP ≤ 500ms p95
- Support 100+ clips
- Memory ≤ 600MB peak
- 90% prefetch hit rate

### Phase 3
- 60fps 3D transitions
- Speed control < 100ms latency
- Device compatibility maintained

---

**Document Version**: 3.0 (Hybrid Loading Strategy)  
**Last Updated**: After deep analysis and iOS best practices research  
**Status**: Ready for Phase 1 implementation
