# Tape Player Rebuild Roadmap
## Phased Implementation with Functional Deliverables

---

## Overview

This roadmap divides the complete rebuild plan into **3 phases**. Each phase produces a **fully functional, testable player** that can be shipped independently. Architecture is designed to be extensible, allowing us to build more on top in later phases.

**Key Principles**:
- **Each phase is shippable**: You can stop at any phase and have a working player
- **Incremental complexity**: Start simple, add sophistication in later phases
- **Leverage existing code**: Use `TapeCompositionBuilder` directly (it already does parallel loading)
- **Native APIs first**: Use Apple's frameworks directly
- **Feature flag per phase**: Enable/disable phase features independently

---

## Phase 1: Simple Foundation + Fast Playback
**Goal**: Fast startup, smooth transitions, never-stuck playback

**Deliverable**: Production-ready player for small-to-medium tapes (up to ~30 clips) with 2D transitions

### Core Insight

**`TapeCompositionBuilder` already does everything we need:**
- Parallel asset loading using `TaskGroup` (Apple's native way)
- Photos/iCloud handling automatically
- Single composition building
- Transition support via `AVVideoComposition`

**Phase 1 should be simple:** Just call the builder directly. No custom orchestration needed.

### Components

**1. SimplePlayerEngine** (~100 lines)
- ✅ Own AVPlayer, manage playback state
- ✅ @Published properties: isPlaying, currentTime, currentClipIndex, isBuffering, error
- ✅ Basic API: prepare, play, pause, seek, seekToClip, teardown
- ✅ Time/end/stall observers
- ✅ Basic interruption handling (pause on phone call)
- ✅ Calls `builder.buildPlayerItem(for: tape)` directly
- ❌ Playback speed control (defer to Phase 3)
- ❌ Background audio continuation (defer to Phase 2)

**2. TapeCompositionBuilder** (Already Exists ✅)
- ✅ Parallel loading using `TaskGroup` (built-in)
- ✅ Photos/iCloud support (built-in)
- ✅ Single composition building (built-in)
- ✅ Transition support (built-in)
- ✅ Image-to-video encoding (built-in)
- **Use directly - no wrapper needed**

**3. PlayerView** (Minimal Changes ~20 lines)
- ✅ Full-screen black background
- ✅ VideoPlayer overlay
- ✅ Glass "Loading Tape" overlay (when engine.isBuffering)
- ✅ Controls: Play/Pause, Previous/Next, Progress scrubber, Dismiss
- ✅ Auto-hide controls after 3s
- ✅ Tap to reveal controls
- ✅ AirPlay button (AVRoutePickerView)
- ✅ Accessibility: VoiceOver labels, Reduce Motion support
- ❌ Thumbnail scrubbing (defer to Phase 2)
- ❌ Playback speed control UI (defer to Phase 3)

**4. TransitionSequence** (Shared Utility - Optional)
- ✅ Seeded RNG for randomise (deterministic)
- ✅ Duration clamping (per-clip + global 0.5s for randomise)
- ✅ Shared between playback and export
- **Note**: May already exist in export code, reuse if available

### What We DON'T Need (Phase 1)

- ❌ **AssetLoader**: Builder already loads assets
- ❌ **BackgroundAssetService**: Builder's TaskGroup handles parallel loading efficiently
- ❌ **ClipPrefetcher**: Not needed for single composition
- ❌ **PlaybackCoordinator**: Builder already orchestrates loading
- ❌ Progressive composition rebuilding
- ❌ Complex state machines

### Implementation Flow

```
1. User taps play
   ↓
2. TapePlayerView.onAppear
   ↓
3. engine.prepare(tape:)
   - Set isBuffering = true (immediate - shows loading)
   ↓
4. builder.buildPlayerItem(for: tape)
   - TaskGroup loads ALL clips in parallel
   - Handles Photos/iCloud automatically
   - Builds single AVMutableComposition
   - Returns PlayerComposition
   ↓
5. engine.install(composition)
   - Creates AVPlayer
   - Sets playerItem
   - Installs observers
   - Auto-plays
   - Set isBuffering = false (hides loading)
   ↓
6. Playback starts smoothly
```

### Acceptance Criteria

- ✅ **TTFMP**: ≤ 2.0s p95 (parallel loading via TaskGroup)
- ✅ **Stall Rate**: ≤ 1 stall per 5 minutes p95
- ✅ **Transition Smoothness**: No visible hiccups at boundaries
- ✅ **Visual Parity**: Transitions match export output
- ✅ **No Jumping**: Single composition = no mid-playback replacements
- ✅ **Basic Lifecycle**: Handles phone calls, app switching (pauses)
- ✅ **Accessibility**: VoiceOver works, Reduce Motion respected

### Feature Flag
- `playbackEngineV2Phase1`: Enable/disable Phase 1 features

### Testing Checklist
- [ ] TTFMP validation (local and iCloud clips)
- [ ] Stall rate measurement (5-minute playback sessions)
- [ ] Transition visual parity vs export
- [ ] Memory usage (≤ 400MB peak)
- [ ] Error scenarios (Photos denied, timeout, missing asset)
- [ ] Interruption handling (phone call during playback)
- [ ] Large tape testing (30 clips)

### Estimated Timeline
- **Duration**: 1 week
- **Dependencies**: None (uses existing builder)
- **Risk**: Very low (simple, proven pattern)

---

## Phase 2: Scalability + Performance Optimization
**Goal**: Handle large tapes efficiently, memory-conscious, network-adaptive

**Deliverable**: Production-ready player for tapes of any size (50+ clips) with optimized memory and network usage

### New Components

**1. CompositionStrategy Protocol** (New)
- ✅ `protocol CompositionStrategy`
- ✅ `SingleCompositionStrategy` (Phase 1 behavior, refactored)
- ✅ `SegmentCompositionStrategy` (chunks of 10-15 clips)
- ✅ `QueueCompositionStrategy` (AVQueuePlayer for 50+ clips)
- ✅ Strategy selection based on clip count and device capabilities

**2. Progressive Loading Service** (New)
- ✅ Background prefetch for upcoming clips
- ✅ Priority queue (current → next → next+1 → rest)
- ✅ Network-aware (Wi-Fi vs cellular)
- ✅ Memory-conscious (pause on memory warnings)

**3. BackgroundAssetService** (New)
- ✅ Persistent background queue for iCloud assets
- ✅ BGProcessingRequest for background execution
- ✅ Bandwidth estimation
- ✅ Network adaptation

**4. ThumbnailGenerator** (New)
- ✅ Generate thumbnails for scrubbing UI
- ✅ Cache on disk (keyed by clip ID + timestamp)
- ✅ Lazy loading: generate on-demand if not cached

**5. PlaybackCoordinator** (New - If Needed)
- ✅ Orchestrate progressive loading
- ✅ Manage composition swapping
- ✅ Timeline preservation during swaps
- ✅ Strategy selection

### Acceptance Criteria

- ✅ **Large Tape Support**: 100+ clips without memory issues
- ✅ **TTFMP**: ≤ 500ms p95 (progressive loading)
- ✅ **Background Prefetch**: 90% hit rate for iCloud assets
- ✅ **Memory**: ≤ 600MB peak for large tapes
- ✅ **Network Adaptation**: Automatic throttling on cellular

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

### Estimated Timeline
- **Duration**: 2-3 weeks
- **Dependencies**: Phase 1 complete (Phase 2 optional)
- **Risk**: Medium (Metal rendering complexity)

---

## Key Architectural Decisions

### Why Simple Phase 1?
1. **Builder already does parallel loading** - No need to duplicate
2. **Native TaskGroup** - Apple's recommended way
3. **Single composition** - Simple, reliable, no jumping
4. **Fast implementation** - ~120 lines vs 1500+ over-engineered version
5. **Easy to extend** - Foundation supports Phase 2/3 additions

### Why No Coordinator in Phase 1?
- **Unnecessary**: Builder already orchestrates loading
- **Over-engineering**: Direct call is sufficient
- **Easy to add**: Can wrap in coordinator for Phase 2 if needed

### Why No BackgroundAssetService in Phase 1?
- **TaskGroup is sufficient**: Already loads in parallel efficiently
- **Not needed**: Single composition doesn't need background prefetch
- **Phase 2 feature**: Add when we need progressive compositions

### Why Use Builder Directly?
- **Zero duplication**: Builder already handles everything
- **Native APIs**: Uses TaskGroup, PHImageManager correctly
- **Proven**: Existing export code uses it successfully
- **Simple**: One call, get composition

---

## Migration Path

### Phase 1 → Phase 2
- Wrap engine in coordinator (if needed)
- Add strategy protocol
- Add progressive loading service
- No breaking changes to engine API
- Feature flag: `playbackEngineV2Phase2`

### Phase 2 → Phase 3
- Add transition renderer protocol
- Add Metal renderer
- Extend builder with renderer injection
- Backward compatible
- Feature flag: `playbackEngineV2Phase3`

---

## Success Metrics

### Phase 1
- TTFMP ≤ 2.0s p95
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

**Document Version**: 2.0 (Rewritten based on research)  
**Last Updated**: After clean architecture analysis  
**Status**: Ready for Phase 1 implementation
