# Tape Player Rebuild Roadmap
## Phased Implementation with Functional Deliverables

---

## Overview

This roadmap divides the complete rebuild plan into **3 phases**. Each phase produces a **fully functional, testable player** that can be shipped independently. Architecture is designed to be extensible, allowing us to build more on top in later phases.

**Key Principles**:
- **Each phase is shippable**: You can stop at any phase and have a working player
- **Incremental complexity**: Start simple, add sophistication in later phases
- **Extensibility built-in**: Architecture supports future enhancements without rebuilds
- **Feature flag per phase**: Enable/disable phase features independently

---

## Phase 1: Foundation + Fast, Reliable Playback
**Goal**: Fast startup, smooth transitions, never-stuck playback, background prefetch

**Deliverable**: Production-ready player for small-to-medium tapes (up to ~30 clips) with 2D transitions

### Core Components

**1. PlayerEngine** (Basic)
- ✅ Own AVPlayer, manage playback state
- ✅ @Published properties: isPlaying, currentTime, currentClipIndex, isBuffering, error
- ✅ Basic API: prepare, play, pause, seek, seekToClip, teardown
- ✅ Time/boundary/end/stall observers
- ✅ Basic interruption handling (pause on phone call)
- ❌ Playback speed control (defer to Phase 3)
- ❌ Background audio continuation (defer to Phase 2)

**2. AssetLoader** (Robust)
- ✅ Request AVAsset (local + Photos/iCloud)
- ✅ Network access enabled for iCloud
- ✅ Progress callbacks, cancellation
- ✅ Timeout/retry with exponential backoff
- ✅ In-memory LRU cache (20 entries max)
- ✅ Error classification
- ❌ Disk cache (defer to Phase 2)

**3. BackgroundAssetService** (Basic)
- ✅ Priority queue for iCloud asset prefetch
- ✅ Prioritize: current → next → next+1 → rest
- ✅ Network detection (Wi-Fi vs cellular)
- ✅ Aggressive on Wi-Fi, conservative on cellular
- ✅ Progress callbacks
- ❌ Background execution with BGProcessingRequest (defer to Phase 2)
- ❌ Bandwidth estimation (defer to Phase 2)

**4. ClipPrefetcher** (Always-Running)
- ✅ Track current playback position
- ✅ Pre-resolve next 2 clips in background
- ✅ Pause/resume based on playback state
- ✅ Back-pressure: stop on memory warnings
- ✅ Integrate with BackgroundAssetService
- ❌ Device capability adaptation (defer to Phase 3)

**5. CompositionBuilder** (2D Transitions Only)
- ✅ Build AVMutableComposition + AVVideoComposition
- ✅ BasicTransitionRenderer (hardcoded, no protocol yet)
- ✅ Support: none, crossfade, slideLR, slideRL, randomise
- ✅ Ken Burns for images
- ✅ Generate temporary video assets for stills
- ✅ Audio ramps for crossfades
- ✅ Single composition strategy (all clips in one)
- ❌ Segment-based or queue-based strategies (defer to Phase 2)
- ❌ TransitionRenderer protocol (defer to Phase 3)

**6. PlaybackCoordinator** (Orchestrator)
- ✅ Coordinate Engine + Builder + Preloader + BackgroundAssetService
- ✅ Warmup → progressive → final flow
- ✅ Progress callbacks: warmup ready, clip ready, completion, error
- ✅ Error handling, skips, timeouts
- ❌ Strategy selection (single composition only in Phase 1)

**7. PlayerView** (SwiftUI UI)
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

**8. TransitionSequence** (Shared Utility)
- ✅ Seeded RNG for randomise (deterministic)
- ✅ Duration clamping (per-clip + global 0.5s for randomise)
- ✅ Shared between playback and export

### Acceptance Criteria

- ✅ **TTFMP**: ≤ 500ms p95 for local clips, ≤ 2.0s p95 for iCloud
- ✅ **Stall Rate**: ≤ 1 stall per 5 minutes p95
- ✅ **Transition Smoothness**: No visible hiccups at boundaries
- ✅ **Visual Parity**: Transitions match export output
- ✅ **Background Prefetch**: iCloud assets ready before playback reaches them
- ✅ **Next-Clip Pipeline**: Always 1-2 clips ahead
- ✅ **Basic Lifecycle**: Handles phone calls, app switching (pauses)
- ✅ **Accessibility**: VoiceOver works, Reduce Motion respected

### Feature Flag
- `playbackEngineV2Phase1`: Enable/disable Phase 1 features

### Testing Checklist
- [ ] TTFMP validation (local and iCloud clips)
- [ ] Stall rate measurement (5-minute playback sessions)
- [ ] Transition visual parity vs export
- [ ] Background prefetch verification (iCloud assets)
- [ ] Next-clip pipeline verification (always ahead)
- [ ] Memory usage (≤ 400MB peak)
- [ ] Error scenarios (Photos denied, timeout, missing asset)
- [ ] Interruption handling (phone call during playback)

### Estimated Timeline
- **Duration**: 2-3 weeks
- **Dependencies**: None (starts from clean slate)
- **Risk**: Low (proven patterns, incremental approach)

---

## Phase 2: Scalability + Performance Optimization
**Goal**: Handle large tapes efficiently, memory-conscious, network-adaptive, production-ready error handling

**Deliverable**: Production-ready player for tapes of any size (50+ clips) with optimized memory and network usage

### New Components

**1. CompositionStrategy Protocol** (New)
- ✅ `protocol CompositionStrategy`
- ✅ `SingleCompositionStrategy` (Phase 1 behavior, refactored)
- ✅ `SegmentCompositionStrategy` (chunks of 10-15 clips)
- ✅ `QueueCompositionStrategy` (AVQueuePlayer for 50+ clips)
- ✅ Strategy selection based on clip count and device capabilities

**2. CompositionBuilder** (Enhanced)
- ✅ Support all composition strategies
- ✅ Progressive segment building
- ✅ Queue item management
- ✅ Disk cache for encoded image assets (keyed by hash + duration + transform)
- ✅ Cache TTL: 7 days, size limit: 200MB

**3. ThumbnailGenerator** (New)
- ✅ Generate thumbnails for all clips in background
- ✅ Cache thumbnails on disk (keyed by clip ID + timestamp)
- ✅ Lazy loading: generate on-demand if not cached
- ✅ Keyframe extraction for video, image extraction for photos
- ✅ Progress callbacks for UI

**4. MemoryManager** (New)
- ✅ Respond to memory warnings
- ✅ Aggressive cache eviction on pressure
- ✅ Reduce prefetch window to 1 clip on pressure
- ✅ Monitor peak memory usage
- ✅ Log memory footprint for diagnostics

**5. NetworkMonitor** (New)
- ✅ Detect Wi-Fi vs cellular (NWPathMonitor)
- ✅ Estimate bandwidth (optional)
- ✅ Pause prefetch on cellular if user preference set
- ✅ Adapt prefetch window based on network conditions

**6. PlayerEngine** (Enhanced)
- ✅ Background audio continuation (AVAudioSession configuration)
- ✅ Save/restore playback state on app lifecycle
- ✅ Resume playback after interruption if appropriate
- ❌ Playback speed control (defer to Phase 3)

**7. BackgroundAssetService** (Enhanced)
- ✅ Background execution with BGProcessingRequest
- ✅ Bandwidth estimation
- ✅ User preference: "Only prefetch on Wi-Fi"
- ✅ Respect system "Low Data Mode"

**8. PlayerView** (Enhanced)
- ✅ Thumbnail scrubbing (show thumbnails in progress bar)
- ✅ Network indicator (optional: show when downloading from iCloud)
- ✅ Memory pressure indicator (optional: show when memory constrained)

### Enhanced Components

**AssetLoader**:
- ✅ Disk cache for resolved AVAssets (optional, for frequently accessed)
- ✅ Cache size limits and TTL

**ClipPrefetcher**:
- ✅ Adaptive window sizing based on memory and network
- ✅ Device capability awareness (prefetch less on older devices)

### Acceptance Criteria

- ✅ **Large Tapes**: Smooth playback of 50+ clip tapes
- ✅ **Memory Efficiency**: ≤ 400MB peak on modern iPhones, ≤ 250MB on older devices
- ✅ **Network Adaptation**: Prefetch adapts to Wi-Fi vs cellular
- ✅ **Thumbnail Scrubbing**: Smooth scrubbing with thumbnails
- ✅ **Error Recovery**: Comprehensive error handling with user feedback
- ✅ **Background Playback**: Continues when app backgrounds (if enabled)

### Feature Flag
- `playbackEngineV2Phase2`: Enable/disable Phase 2 features

### Testing Checklist
- [ ] Large tape playback (50+ clips)
- [ ] Memory pressure scenarios
- [ ] Network condition variations (Wi-Fi, cellular, no network)
- [ ] Thumbnail generation and caching
- [ ] Background playback continuation
- [ ] Error recovery (various error types)
- [ ] Cache eviction under memory pressure
- [ ] Strategy selection (single vs segment vs queue)

### Estimated Timeline
- **Duration**: 2-3 weeks
- **Dependencies**: Phase 1 complete
- **Risk**: Medium (introduces complexity, needs thorough testing)

---

## Phase 3: Extensibility + Advanced Features
**Goal**: 3D transitions, extensible architecture, device adaptation, advanced audio

**Deliverable**: Production-ready player with 3D transitions and fully extensible architecture

### New Components

**1. TransitionRenderer Protocol** (New)
- ✅ `protocol TransitionRenderer`
- ✅ Factory pattern: `TransitionRendererFactory`
- ✅ Device capability detection (Metal support, chip generation)

**2. Layer3DTransitionRenderer** (New)
- ✅ Implement TransitionRenderer protocol
- ✅ Support: `.cube`, `.pageFlip`, `.rotate3D`
- ✅ Uses CALayer + CATransform3D
- ✅ Requires: A12+ chip for performance
- ✅ Fallback to crossfade on older devices

**3. DeviceCapabilities** (New)
- ✅ Detect Metal support
- ✅ Detect chip generation (A12+, A14+, etc.)
- ✅ Detect available memory
- ✅ Adapt strategies based on capabilities

**4. AudioMixer** (New)
- ✅ Audio normalization across clips
- ✅ Optional audio ducking during transitions
- ✅ Multi-track audio handling
- ✅ User preference: Enable/disable normalization

**5. PlayerEngine** (Enhanced)
- ✅ Playback speed control (0.5x, 1x, 1.5x, 2x)
- ✅ `setPlaybackRate(_ rate: Float)` API
- ✅ UI control for speed selection

**6. PlayerView** (Enhanced)
- ✅ Playback speed control UI (dropdown or button)
- ✅ 3D transition preview (optional: see transition before committing)
- ✅ Advanced audio controls (normalization toggle)

### Enhanced Components

**CompositionBuilder**:
- ✅ Use TransitionRenderer protocol (replace hardcoded BasicTransitionRenderer)
- ✅ Select renderer via factory based on transition type and device capabilities
- ✅ Support all transition types (2D + 3D)

**TransitionSequence**:
- ✅ Support 3D transition types in randomise pool (optional)
- ✅ User preference: Include 3D in randomise, or 2D only

### Acceptance Criteria

- ✅ **3D Transitions**: Smooth cube, pageFlip, rotate3D transitions
- ✅ **Device Adaptation**: Automatically selects appropriate renderer based on device
- ✅ **Extensibility**: Easy to add new transition renderers via protocol
- ✅ **Playback Speed**: Smooth playback at 0.5x, 1.5x, 2x speeds
- ✅ **Audio Mixing**: Normalized audio levels, optional ducking
- ✅ **Performance**: 3D transitions don't cause frame drops on A12+ devices

### Feature Flag
- `playbackEngineV2Phase3`: Enable/disable Phase 3 features

### Testing Checklist
- [ ] 3D transitions on A12+ devices
- [ ] Fallback to 2D on older devices
- [ ] Playback speed control (all rates)
- [ ] Audio normalization verification
- [ ] Device capability detection accuracy
- [ ] Extensibility: Add custom transition renderer
- [ ] Performance: Frame drop rate during 3D transitions

### Estimated Timeline
- **Duration**: 2-3 weeks
- **Dependencies**: Phase 2 complete
- **Risk**: Medium-High (3D transitions are complex, performance-sensitive)

---

## Architecture Extensibility (Built Across All Phases)

### Protocol-Based Design
- **TransitionRenderer**: Add new transitions without touching core code
- **CompositionStrategy**: Add new strategies (e.g., streaming) without rebuild
- **PrefetchStrategy**: Plug in different prefetch algorithms
- **DeviceCapabilities**: Extend capability detection for future devices

### Dependency Injection
- All major components accept dependencies via initializers
- Enables testing with mocks
- Allows swapping implementations

### Feature Flags
- Per-phase flags allow incremental rollout
- Easy rollback if issues found
- A/B testing capability

---

## Risk Mitigation

### Phase 1 Risks
- **Risk**: Background prefetch might not be fast enough
- **Mitigation**: Start prefetch immediately when tape opens, aggressive warmup window

- **Risk**: Memory pressure from too many prefetched assets
- **Mitigation**: Strict cache limits, back-pressure signals, memory warning handlers

### Phase 2 Risks
- **Risk**: Segment/queue strategies might introduce swapping overhead
- **Mitigation**: Only use for large tapes, thorough performance testing

- **Risk**: Thumbnail generation might be slow
- **Mitigation**: Background generation, aggressive caching, lazy loading

### Phase 3 Risks
- **Risk**: 3D transitions might cause frame drops
- **Mitigation**: Device capability detection, fallback to 2D, performance profiling

- **Risk**: Complex architecture might be hard to maintain
- **Mitigation**: Clear protocols, comprehensive tests, documentation

---

## Success Metrics (All Phases)

### Performance
- **TTFMP**: ≤ 500ms local, ≤ 2s iCloud (p95)
- **Stall Rate**: ≤ 1 per 5 minutes (p95)
- **Memory**: ≤ 400MB peak on modern devices
- **Frame Drops**: < 1% during transitions

### Reliability
- **Error Recovery**: Graceful handling of all error types
- **Background Prefetch**: iCloud assets ready before needed
- **Interruption Handling**: Smooth pause/resume

### User Experience
- **Smoothness**: No visible hiccups, seamless transitions
- **Accessibility**: Full VoiceOver support, Reduce Motion
- **Extensibility**: Easy to add new features

---

## Rollout Strategy

### Phase 1 Rollout
1. Internal testing (1 week)
2. Beta to 10% users (1 week)
3. Monitor metrics, fix issues
4. Rollout to 50% users (1 week)
5. Full rollout if metrics acceptable

### Phase 2 Rollout
1. Feature flag: Enable Phase 2 for beta users
2. Monitor large tape performance
3. Gradual rollout based on metrics

### Phase 3 Rollout
1. Feature flag: Enable Phase 3 for beta users
2. Monitor 3D transition performance
3. Gradual rollout with device capability gating

---

## Documentation Requirements

### Per Phase
- Architecture diagrams
- API documentation
- Testing guide
- Troubleshooting guide
- Performance benchmarks

### Overall
- Complete architecture overview
- Extensibility guide (how to add new transitions)
- Migration guide (from old to new player)
- Telemetry guide (what metrics to monitor)

---

**Roadmap Version**: 1.0  
**Last Updated**: Post-rebuild planning  
**Status**: Ready for Phase 1 implementation

