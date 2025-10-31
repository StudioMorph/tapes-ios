# Tape Player Complete Rebuild Plan
## Memories-Level Experience with Full Scalability & Extensibility

---

## Executive Summary

**Goal**: Build a production-ready, scalable, extensible tape player that delivers a "Memories"-level smooth experience with seamless transitions, progressive loading, background prefetch, and future-ready architecture for 3D transitions and advanced features.

**Architecture Principles**:
- **Extensibility First**: Protocol-based design allows plugging in new transition renderers, prefetch strategies, composition builders
- **Progressive Delivery**: Each phase produces a functional, testable player
- **Scalability Built-In**: Supports small tapes (single composition) and large tapes (hybrid strategies)
- **Performance & Reliability**: Background services, memory management, network adaptation

---

## Core Architecture

### 1. PlayerEngine (ObservableObject, @MainActor)
**Purpose**: Owns AVPlayer, manages playback state, handles lifecycle

**Responsibilities**:
- Own single AVPlayer instance
- Manage AVPlayerItem swapping with time preservation
- Install/remove observers (time, boundary, end, stall)
- Expose @Published state: `isPlaying`, `currentTime`, `currentClipIndex`, `isBuffering`, `isFinished`, `error`, `timeline`
- Handle playback interruptions (phone calls, backgrounding)
- Support playback speed control (0.5x, 1x, 1.5x, 2x)

**API**:
```swift
func prepare(tape: Tape) async
func play()
func pause()
func seek(to seconds: Double, autoplay: Bool)
func seekToClip(index: Int, autoplay: Bool)
func setPlaybackRate(_ rate: Float) // 0.5, 1.0, 1.5, 2.0
func replace(with composition: PlayerComposition, autoplay: Bool, preserveTime: CMTime?)
func teardown()
```

**Lifecycle Handling**:
- Configure AVAudioSession for background playback
- Handle interruption begin/end notifications
- Save/restore playback state on app lifecycle events
- Resume playback after interruption if appropriate

---

### 2. BackgroundAssetService (Persistent Background Queue)
**Purpose**: Proactively fetch iCloud assets in background, maintain priority queue

**Responsibilities**:
- Maintain priority queue of iCloud assets to fetch
- Prioritize: current clip → next clip → next+1 → rest
- Network-aware: aggressive on Wi-Fi, conservative on cellular
- Background execution when possible (BGProcessingRequest)
- Progress callbacks for UI (optional loading indicators)
- Handle Photos library authorization changes

**API**:
```swift
func enqueue(assetIdentifiers: [String], priority: FetchPriority)
func cancel(assetIdentifiers: [String])
func prefetchForTape(_ tape: Tape, startingAt index: Int)
func pausePrefetch()
func resumePrefetch()
```

**Network Adaptation**:
- Detect connection type (Wi-Fi vs cellular)
- Estimate bandwidth
- Adjust prefetch aggressiveness based on network conditions
- Pause on cellular if user preference set

---

### 3. AssetLoader (Async Request Handler)
**Purpose**: Fetch individual AVAssets with robust error handling

**Responsibilities**:
- Request AVAsset for clip (local URL or Photos identifier)
- Support iCloud assets with network access enabled
- Progress callbacks, cancellation support
- Timeout/retry with exponential backoff
- Classify errors (denied, timeout, unavailable, etc.)
- Cache resolved assets in-memory (LRU) with size limits

**API**:
```swift
func requestAVAsset(for clip: Clip, timeout: TimeInterval) async throws -> AVAsset
func requestAVAssetWithProgress(for clip: Clip, timeout: TimeInterval, progress: @escaping (Double) -> Void) async throws -> AVAsset
```

**Error Types**:
- `photosAccessDenied`
- `timeout`
- `assetUnavailable`
- `networkError`
- `cancelled`

---

### 4. ClipPrefetcher (Always-Running Background Task)
**Purpose**: Maintain next 1-2 clips ready while playing current clip

**Responsibilities**:
- Track current playback position (from PlayerEngine)
- Pre-resolve next 2-3 clips in background
- Pause when user pauses playback
- Resume when playback starts
- Back-pressure: stop prefetch if memory pressure or no playback progress
- Integrate with BackgroundAssetService for iCloud items
- Emit ready contexts as they resolve

**API**:
```swift
func startPrefetching(for tape: Tape, currentIndex: Int)
func pausePrefetch()
func resumePrefetch()
func stopPrefetch()
func getNextReadyClip() -> ClipAssetContext?
```

**Back-Pressure Signals**:
- Memory warnings from system
- Playback paused > 30 seconds
- User explicitly stopped playback
- App backgrounded without background audio permission

---

### 5. TransitionRenderer Protocol (Extensible)
**Purpose**: Plugin architecture for transition styles (2D, 3D, custom)

**Protocol**:
```swift
protocol TransitionRenderer {
    func renderTransition(
        from: ClipAssetContext,
        to: ClipAssetContext,
        transition: TransitionDescriptor,
        renderSize: CGSize,
        composition: AVMutableComposition,
        videoTracks: [AVMutableCompositionTrack]
    ) -> [AVVideoCompositionInstructionProtocol]
    
    var supportedTransitionTypes: [TransitionType] { get }
    var requiresMetal: Bool { get } // For device capability detection
}
```

**Implementations**:

**BasicTransitionRenderer** (Phase 1):
- Supports: `.none`, `.crossfade`, `.slideLR`, `.slideRL`
- Uses AVMutableVideoCompositionLayerInstruction
- 2D transforms (CGAffineTransform)

**Layer3DTransitionRenderer** (Phase 3):
- Supports: `.cube`, `.pageFlip`, `.rotate3D`, etc.
- Uses CALayer + CATransform3D
- Requires: A12+ chip for performance

**MetalTransitionRenderer** (Future):
- Supports: Custom shader-based transitions
- Uses AVVideoCompositor + Metal shaders
- Maximum flexibility and performance

**Factory Pattern**:
- `TransitionRendererFactory.create(for: TransitionType, deviceCapabilities: DeviceCapabilities) -> TransitionRenderer`
- Automatically selects appropriate renderer based on transition type and device

---

### 6. CompositionBuilder (Timeline + Instructions Generator)
**Purpose**: Build AVFoundation compositions with transitions

**Responsibilities**:
- Build AVMutableComposition + AVVideoComposition progressively
- Use TransitionRenderer protocol for extensibility
- Handle Ken Burns for images
- Generate temporary video assets for still images
- Apply audio mix ramps for crossfades
- Support partial compositions (warmup) and full compositions
- Unified render size policy (1080×1920 or 1920×1080)

**API**:
```swift
func buildPlayerItem(for tape: Tape) async throws -> PlayerComposition
func buildPlayerItem(for tape: Tape, contexts: [ClipAssetContext]) throws -> PlayerComposition
func makeTimeline(for tape: Tape, contexts: [ClipAssetContext]) -> Timeline
func resolveClipContext(for clip: Clip, index: Int) async throws -> ClipAssetContext
```

**Image Handling**:
- Encode still images to temporary H.264 assets
- Apply Ken Burns via transform ramps
- Cache encoded assets on disk (keyed by image hash + duration + transform)
- Clamp image dimensions (max 1920px long side)

**Progressive Building**:
- Warmup: build composition for first N clips (e.g., 5 clips)
- Progressive: rebuild as more clips become available
- Final: rebuild when all clips loaded

---

### 7. PlaybackCoordinator (Orchestrator)
**Purpose**: Coordinate Engine + Builder + Preloader + BackgroundAssetService

**Responsibilities**:
- Orchestrate preparation flow: warmup → progressive → final
- Coordinate ClipPrefetcher with current playback position
- Feed CompositionBuilder contexts as they resolve
- Handle errors, skips, timeouts
- Emit progress callbacks: warmup ready, clip ready, completion, error

**API**:
```swift
func prepare(
    tape: Tape,
    onWarmupReady: @escaping (PreparedResult) -> Void,
    onProgress: @escaping (PreparedResult) -> Void,
    onCompletion: @escaping (PreparedResult) -> Void,
    onSkip: @escaping (SkipReason, Int) -> Void,
    onError: @escaping (Error) -> Void
)
func cancel()
```

**Flow**:
1. Trigger BackgroundAssetService to prefetch all iCloud assets
2. Start ClipPrefetcher for first window
3. As contexts resolve, feed to CompositionBuilder
4. Build warmup composition → emit onWarmupReady
5. Continue prefetching → build progressive compositions → emit onProgress
6. When all clips ready → build final composition → emit onCompletion

---

### 8. ThumbnailGenerator (Background Service)
**Purpose**: Generate thumbnails for scrubbing UI

**Responsibilities**:
- Generate thumbnails for all clips in background
- Cache thumbnails on disk (keyed by clip ID + timestamp)
- Lazy loading: generate on-demand if not cached
- Support keyframe extraction for video, image extraction for photos
- Emit progress for UI (thumbnail ready callbacks)

**API**:
```swift
func generateThumbnail(for clip: Clip, at time: TimeInterval) async throws -> UIImage
func generateThumbnails(for tape: Tape, count: Int) async -> [ThumbnailResult]
func getCachedThumbnail(for clip: Clip) -> UIImage?
```

---

### 9. PlayerView (SwiftUI, Thin UI Layer)
**Purpose**: Full-screen player UI with controls and overlays

**Responsibilities**:
- Full-screen black background
- VideoPlayer overlay (full screen)
- Glass "Loading Tape" overlay (when engine.isBuffering)
- Controls overlay: header (dismiss), progress bar, play controls
- Auto-hide controls after 3s (preserve user intent)
- Tap anywhere to reveal controls
- AirPlay button (AVRoutePickerView) when routes available
- Accessibility: VoiceOver labels, Reduce Motion support

**Components**:
- `PlayerLoadingOverlay`: Glass spinner + "Loading Tape" text
- `PlayerControls`: Play/Pause, Previous/Next buttons
- `PlayerProgressBar`: Scrubbable progress with thumbnails (optional)
- `PlayerHeader`: Dismiss button, clip counter
- `AirPlayButton`: Native AVRoutePickerView

**State Binding**:
- Bind to PlayerEngine @Published properties
- No direct AVPlayer ownership
- Minimal business logic in view

---

## Scalability Strategy

### Small Tapes (<20 clips)
- **Strategy**: Single AVComposition for entire tape
- **Why**: Simple, efficient, no swapping overhead
- **Memory**: All clips in one composition

### Medium Tapes (20-50 clips)
- **Strategy**: Segment-based compositions (chunks of 10-15 clips)
- **Why**: Balance memory vs swapping overhead
- **Implementation**: Swap segments seamlessly as playback progresses

### Large Tapes (50+ clips)
- **Strategy**: AVQueuePlayer with dynamic item loading
- **Why**: Memory-efficient, only keep active items loaded
- **Implementation**: Preload next 3-5 items, unload played items

**Detection**:
- Auto-detect tape size at prepare time
- Select strategy based on clip count and device capabilities
- Expose strategy as enum for testing/debugging

---

## Memory Management

### In-Memory Cache
- **ClipAssetContext cache**: LRU, max 20 entries
- **Resolved AVAsset cache**: LRU, max 10 entries
- **Thumbnail cache**: LRU, max 50 images

### Disk Cache
- **Encoded image assets**: Keyed by image hash + duration + transform
- **Thumbnails**: Keyed by clip ID + timestamp
- **TTL**: 7 days for image assets, 30 days for thumbnails
- **Size limit**: 500MB total, LRU eviction

### Memory Pressure Handling
- **Observer**: Respond to UIApplication.didReceiveMemoryWarningNotification
- **Actions**: 
  - Aggressively evict caches
  - Reduce prefetch window to 1 clip
  - Pause non-critical background tasks
  - Log memory footprint for diagnostics

### Memory Monitoring
- Track peak memory usage during playback
- Alert if approaching device limits
- Adapt prefetch/composition strategy based on available memory

---

## Network Adaptation

### Connection Detection
- Monitor network reachability (NWPathMonitor)
- Detect Wi-Fi vs cellular
- Estimate bandwidth (optional)

### Prefetch Strategy
- **Wi-Fi**: Aggressive (prefetch 5+ clips ahead)
- **Cellular**: Conservative (prefetch 1-2 clips ahead)
- **No Network**: Pause prefetch, show error if iCloud asset needed

### User Preferences
- Optional setting: "Only prefetch on Wi-Fi"
- Respect system "Low Data Mode" setting
- Pause prefetch if user sets cellular data limit

---

## Transition System

### Supported Types (Phase 1)
- `.none`: Hard cut
- `.crossfade`: Opacity ramps
- `.slideLR`: Horizontal slide left-to-right
- `.slideRL`: Horizontal slide right-to-left
- `.randomise`: Seeded deterministic sequence

### Supported Types (Phase 3 - 3D)
- `.cube`: 3D cube rotation
- `.pageFlip`: Page turn effect
- `.rotate3D`: 3D rotation around axis
- Custom: User-defined via TransitionRenderer protocol

### Duration Policy
- Per-boundary: Capped to min(50% of current clip, 50% of next clip)
- Randomise: Additional global cap at 0.5s
- User-adjustable: 0.1s to 2.0s via settings

### Sequence Generation
- Single shared `TransitionSequence` utility (playback + export parity)
- Seeded RNG per tape ID (deterministic randomise)
- Reduce Motion: Coerce slides to crossfade/none

### Render Size
- Fixed: 1080×1920 (portrait) or 1920×1080 (landscape)
- Export parity: Same render size as export for visual consistency
- Slide offsets computed from fixed render width

---

## Audio Handling

### Audio Mix
- **Crossfade**: Volume ramps on incoming/outgoing tracks
- **Slides**: Constant volume (no ramping)
- **Hard Cut**: Constant volume

### Audio Normalization
- Optional: Normalize audio levels across clips
- Prevent jarring volume jumps
- User preference: Enable/disable normalization

### Multi-Track Audio
- Handle clips with multiple audio tracks
- Mix strategy: Use first track, or mix all tracks
- Configurable per tape or global setting

---

## Performance Targets

### Time-to-First-Frame (TTFMP)
- **Local clips**: ≤ 500ms p95
- **iCloud clips**: ≤ 2.0s p95 (with network access)

### Stall Rate
- **Target**: ≤ 1 stall per 5 minutes p95
- **Measurement**: AVPlayerItemPlaybackStallNotification count

### Memory Usage
- **Target**: ≤ 400MB peak on modern iPhones (iPhone 12+)
- **Older devices**: ≤ 250MB peak (iPhone 8/X)

### Frame Drops
- **Target**: < 1% dropped frames during transitions
- **Measurement**: AVPlayerItemVideoOutput frame timing

---

## Error Handling

### Error Taxonomy
- **Asset Errors**: Photos access denied, asset unavailable, timeout
- **Composition Errors**: Missing video track, invalid time range, encoding failed
- **Playback Errors**: Stall, interruption, route lost
- **Network Errors**: No connection, slow connection, download failed

### Recovery Strategies
- **Retry**: Exponential backoff for transient errors
- **Skip**: Mark clip as skipped, continue with available clips
- **Fallback**: Use lower quality asset, or placeholder
- **User Feedback**: Clear error messages, retry affordance

### Logging
- Comprehensive logging via TapesLog.player
- Structured errors for telemetry
- Debug mode: Verbose logging, diagnostic overlays

---

## Telemetry & Observability

### Metrics Tracked
- TTFMP (time-to-first-frame)
- Stall count and duration
- Memory peaks
- Network usage (bytes downloaded)
- Frame drop rate
- Composition build time
- Prefetch hit/miss rate

### Diagnostics
- Debug overlay (DEBUG builds only): Show active transition, clip index, buffer status
- Logging: Structured logs for playback events
- Crash reporting: Capture playback state on crashes

---

## Accessibility

### VoiceOver
- Labels for all controls
- Timecode announcements
- Clip index announcements
- Error announcements

### Reduce Motion
- Detect UIAccessibility.isReduceMotionEnabled
- Coerce slide transitions to crossfade/none
- Disable Ken Burns effect on photos

### Dynamic Type
- Support larger text sizes in controls
- Adjustable hit targets (44×44pt minimum)

---

## AirPlay/Cast Support

### AirPlay (iOS Native)
- AVRoutePickerView embedded in controls
- Visible only when routes available
- Automatic routing when route selected
- Playback continues on external display
- Controls remain on device

### Future: Google Cast (If Needed)
- Similar pattern: Detect devices, show picker, route output
- For now: Focus on AirPlay via AVRoutePickerView

---

## Testing Strategy

### Unit Tests
- Transition sequence determinism
- Duration clamping logic
- AssetLoader error handling
- TransitionRenderer implementations

### Integration Tests
- End-to-end playback flow
- Composition building with various clip types
- Error recovery paths

### Manual QA
- TTFMP validation (local and iCloud)
- Stall rate measurement
- Memory pressure scenarios
- Network condition variations
- Interruption handling (calls, notifications)
- Background playback continuation

---

## Extensibility Points

### TransitionRenderer Protocol
- Plugin architecture for new transition styles
- Easy to add 3D, custom, or user-defined transitions

### PrefetchStrategy Protocol
- Plug in different prefetch algorithms
- Network-aware, user-preference-aware strategies

### CompositionStrategy Protocol
- Hybrid strategies: Single composition, segment-based, queue-based
- Select based on tape size or device capabilities

### DeviceCapabilities Detection
- Metal support, memory class, chip generation
- Adapt strategies based on capabilities

---

## Future Enhancements (Post-Phase 3)

### Advanced Features
- Per-clip transition overrides
- Custom transition curves (ease-in-out, ease-out, linear)
- Audio ducking during transitions
- Playback speed control (0.5x, 1.5x, 2x)
- Loop playback
- Shuffle playback

### Performance
- Metal shader-based transitions
- Hardware-accelerated image encoding
- Parallel composition building

### User Experience
- Transition preview (see transition before committing)
- Thumbnail scrubbing (show thumbnails in progress bar)
- Playback history/resume

---

## Success Criteria

### Phase 1 Deliverable
- ✅ Fast playback start (TTFMP ≤ 500ms local, ≤ 2s iCloud p95)
- ✅ Smooth transitions (no visible hiccups)
- ✅ Background prefetch (iCloud assets ready before needed)
- ✅ Next-clip pipeline (always 1-2 clips ahead)
- ✅ Basic lifecycle handling (interruptions, backgrounding)

### Phase 2 Deliverable
- ✅ Scalable to large tapes (50+ clips)
- ✅ Thumbnail generation for scrubbing
- ✅ Memory-efficient (≤ 400MB peak)
- ✅ Network-aware prefetch
- ✅ Comprehensive error handling

### Phase 3 Deliverable
- ✅ 3D transition support
- ✅ Extensible architecture (protocol-based)
- ✅ Device capability adaptation
- ✅ Advanced audio mixing
- ✅ Production-ready telemetry

---

## Dependencies

### Frameworks
- AVFoundation (core playback)
- AVKit (VideoPlayer component)
- Photos (asset access)
- Network (network monitoring)
- Combine (optional: reactive state)

### System Requirements
- iOS 17+
- Xcode 16+
- Swift 5.10+
- SwiftUI
- Swift Concurrency (async/await)

---

**Document Version**: 1.0  
**Last Updated**: Post-rebuild planning  
**Status**: Ready for phased implementation

