# Placeholder-Based Composition with Seamless Rebuilds - Investigation Report

**Date:** 2024  
**Status:** Investigation Complete - Ready for Implementation  
**Goal:** All assets eventually play, rebuilds happen with zero visual impact

---

## Executive Summary

**Problem:** Current approach builds partial timeline with gaps, requiring complex skip logic. Rebuilds cause visible hiccups.

**Solution:** Build complete timeline upfront with placeholder assets for missing clips. When assets load, rebuild composition and swap seamlessly using `AVPlayer.replaceCurrentItem(with:)` with precise position preservation.

**Key Insight:** Placeholders ensure timeline positions map 1:1 between old and new compositions, enabling seamless swaps.

---

## Architecture Overview

### Current State Analysis

**Timeline Building (`buildPlayerItem`):**
- Only builds segments for ready assets (`readyAssets`)
- Gaps exist where clips are skipped
- Position mapping is complex (non-linear)

**Installation (`install` method):**
```swift
// Current: Creates new player (NOT seamless)
player?.pause()
player = nil
let newPlayer = AVPlayer(playerItem: playerItem)
```

**Position Mapping:**
- `updateCurrentClipIndex()` finds segment containing `currentTime`
- Works but complex with gaps

### Proposed Architecture

**1. Placeholder Creation**
- Black video asset matching render size
- Duration: Use `clip.duration` if available, else default (6s for images, estimated for videos)
- Minimal encoding: 2 frames at 1fps (like image encoding)
- Reusable: Single placeholder asset per render size/duration combination

**2. Complete Timeline Building**
- Build timeline for ALL clips (ready + placeholders)
- Timeline structure:
  ```
  Ready: [0, 2, 4], Missing: [1, 3]
  Timeline:
    - Segment 0: Clip 0 (real) @ 0-5s
    - Segment 1: Placeholder 1 @ 5-8s (estimated 3s)
    - Segment 2: Clip 2 (real) @ 8-13s
    - Segment 3: Placeholder 3 @ 13-16s (estimated 3s)
    - Segment 4: Clip 4 (real) @ 16-21s
  ```

**3. Seamless Swap Mechanism**
- Use `AVPlayer.replaceCurrentItem(with:)` instead of creating new player
- Preserve observers (don't remove/reinstall)
- Map position exactly: Same clip index + same offset = same timeline position
- Swap at safe boundaries:
  - During placeholder segments (black frame - invisible swap)
  - At transition boundaries (brief, acceptable)
  - Immediately if paused (seamless)

---

## Implementation Details

### 1. Placeholder Asset Creation

**Location:** `Tapes/Playback/TapeCompositionBuilder.swift`

**Method:** `createPlaceholderAsset(duration:renderSize:) async throws -> AVAsset`

**Pattern:** Reuse `createVideoAsset` approach but simpler:
- Black pixel buffer (RGB: 0,0,0)
- Same resolution as `renderSize`
- 2 frames at 1fps (minimal encoding)
- No audio track
- Duration matches requested time

**Optimization:** Cache placeholder assets by (renderSize, duration) tuple

```swift
private var placeholderCache: [String: AVAsset] = [:]

func createPlaceholderAsset(duration: Double, renderSize: CGSize) async throws -> AVAsset {
    let key = "\(Int(renderSize.width))x\(Int(renderSize.height))-\(duration)"
    if let cached = placeholderCache[key] {
        return cached
    }
    
    // Create black video (similar to makeSolidColorVideo in tests)
    let asset = try await encodeBlackVideo(duration: duration, size: renderSize)
    placeholderCache[key] = asset
    return asset
}
```

**Estimated Cost:** ~50-100ms per unique placeholder (cached after first creation)

---

### 2. Timeline Building with Placeholders

**Location:** `Tapes/Playback/TapeCompositionBuilder.swift`

**New Method:** `buildPlayerItemWithPlaceholders(for:readyAssets:skippedIndices:allClips:)`

**Key Changes:**
1. Accept `allClips: [Clip]` parameter (entire tape)
2. Build contexts for ready assets
3. Build placeholder contexts for skipped clips
4. Merge into single sorted array
5. Build complete timeline with transitions between ALL consecutive clips

**Timeline Building Logic:**
```swift
func buildPlayerItemWithPlaceholders(
    for tape: Tape,
    readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
    skippedIndices: Set<Int>,
    allClips: [Clip]
) async throws -> PlayerComposition {
    
    // 1. Convert ready assets to contexts
    var contexts: [ClipAssetContext] = []
    for (index, resolved) in readyAssets {
        contexts.append(try await makeContext(resolved, index: index))
    }
    
    // 2. Create placeholder contexts for skipped clips
    let renderSize = self.renderSize(for: tape.orientation)
    for (index, clip) in allClips.enumerated() where skippedIndices.contains(index) {
        let duration = estimateDuration(for: clip)
        let placeholderAsset = try await createPlaceholderAsset(
            duration: duration,
            renderSize: renderSize
        )
        
        // Create ClipAssetContext for placeholder
        let videoTrack = try await placeholderAsset.loadTracks(withMediaType: .video).first!
        contexts.append(ClipAssetContext(
            index: index,
            clip: clip,
            asset: placeholderAsset,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            naturalSize: renderSize,
            preferredTransform: .identity,
            hasAudio: false,
            videoTrack: videoTrack,
            audioTrack: nil,
            motionEffect: nil,
            isTemporaryAsset: true
        ))
    }
    
    // 3. Sort by index (ready + placeholders)
    contexts.sort { $0.index < $1.index }
    
    // 4. Build timeline with ALL clips (transitions between ALL consecutive clips)
    let timeline = makeCompleteTimeline(for: tape, contexts: contexts)
    return try buildPlayerComposition(for: tape, timeline: timeline)
}
```

**Transition Logic:**
- Transitions work normally between ALL consecutive clips (real or placeholder)
- Crossfade with placeholder = fade to/from black
- Slide transitions work (placeholder slides in/out)

---

### 3. Position Mapping (Critical for Seamless Swaps)

**Key Insight:** With placeholders, timeline positions map 1:1

**Mapping Algorithm:**
```swift
func mapTimeToNewTimeline(
    oldTime: CMTime,
    oldTimeline: Timeline,
    newTimeline: Timeline
) -> CMTime {
    // 1. Find which segment contains oldTime in old timeline
    guard let oldSegment = oldTimeline.segments.first(where: { segment in
        let start = CMTimeGetSeconds(segment.timeRange.start)
        let end = start + CMTimeGetSeconds(segment.timeRange.duration)
        let timeSeconds = CMTimeGetSeconds(oldTime)
        return timeSeconds >= start && timeSeconds < end
    }) else {
        // Past end - map to end of new timeline
        return newTimeline.totalDuration
    }
    
    // 2. Calculate offset within segment
    let segmentStart = oldSegment.timeRange.start
    let offsetInSegment = CMTimeSubtract(oldTime, segmentStart)
    
    // 3. Find corresponding segment in new timeline (same clipIndex)
    guard let newSegment = newTimeline.segments.first(where: { 
        $0.clipIndex == oldSegment.clipIndex 
    }) else {
        // Clip removed? Shouldn't happen, but fallback to start
        return .zero
    }
    
    // 4. Map to same position in new segment
    let newTime = CMTimeAdd(newSegment.timeRange.start, offsetInSegment)
    
    // Ensure within bounds
    let newTimeSeconds = CMTimeGetSeconds(newTime)
    let newTotalSeconds = CMTimeGetSeconds(newTimeline.totalDuration)
    if newTimeSeconds >= newTotalSeconds {
        return newTimeline.totalDuration
    }
    
    return newTime
}
```

**Why This Works:**
- Placeholders ensure same clip indices appear at same timeline positions
- Offsets within clips remain identical
- Transitions don't affect mapping (calculated from segment starts)

---

### 4. Seamless Swap Implementation

**Location:** `Tapes/Playback/PlaybackEngine.swift`

**New Method:** `swapCompositionSeamlessly(newComposition:preservingTime:)`

**Key Changes to `install` Method:**
- Rename to `installInitial` (first install)
- New method `swapCompositionSeamlessly` for subsequent swaps
- Use `replaceCurrentItem` instead of creating new player

**Swap Algorithm:**
```swift
private func swapCompositionSeamlessly(
    newComposition: TapeCompositionBuilder.PlayerComposition,
    preservingTime: Double
) async {
    guard let player = player, let oldTimeline = timeline else {
        // Fallback to full install if no player
        await installInitial(composition: newComposition)
        return
    }
    
    // 1. Map time position to new timeline
    let oldCMTime = CMTime(seconds: preservingTime, preferredTimescale: 600)
    let newCMTime = mapTimeToNewTimeline(
        oldTime: oldCMTime,
        oldTimeline: oldTimeline,
        newTimeline: newComposition.timeline
    )
    
    // 2. Detect safe swap point
    let swapPoint = detectSafeSwapPoint(
        currentTime: preservingTime,
        oldTimeline: oldTimeline
    )
    
    // 3. If playing, wait for safe boundary (or swap immediately if in placeholder)
    if isPlaying {
        if swapPoint.isPlaceholder {
            // Swap immediately - placeholder is black, invisible change
            await performSwap(player: player, newItem: newComposition.playerItem, targetTime: newCMTime)
        } else {
            // Wait for next transition boundary
            await waitForSafeBoundary()
            await performSwap(player: player, newItem: newComposition.playerItem, targetTime: newCMTime)
        }
    } else {
        // Paused - swap immediately (seamless)
        await performSwap(player: player, newItem: newComposition.playerItem, targetTime: newCMTime)
    }
    
    // 4. Update timeline reference (preserve observers, state)
    timeline = newComposition.timeline
    duration = CMTimeGetSeconds(newComposition.timeline.totalDuration)
    
    // 5. Update clip index if needed
    updateCurrentClipIndex()
}

private func performSwap(
    player: AVPlayer,
    newItem: AVPlayerItem,
    targetTime: CMTime
) async {
    // Critical: Preserve observers, state
    // Use replaceCurrentItem (doesn't require removing observers)
    player.replaceCurrentItem(with: newItem)
    
    // Seek to equivalent position (preserve playback rate)
    let currentRate = player.rate
    await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    
    // Restore playback rate if was playing
    if currentRate > 0 {
        player.rate = currentRate
    }
}

private func detectSafeSwapPoint(
    currentTime: Double,
    timeline: Timeline
) -> (isPlaceholder: Bool, timeToNextBoundary: Double?) {
    // Find current segment
    guard let segment = timeline.segments.first(where: { segment in
        let start = CMTimeGetSeconds(segment.timeRange.start)
        let end = start + CMTimeGetSeconds(segment.timeRange.duration)
        return currentTime >= start && currentTime < end
    }) else {
        return (isPlaceholder: false, timeToNextBoundary: nil)
    }
    
    // Check if placeholder (has no real asset, or marked as placeholder)
    let isPlaceholder = segment.assetContext.isTemporaryAsset && 
                       segment.assetContext.clip.isPlaceholder
    
    // Calculate time to next transition boundary
    let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
    let segmentEnd = segmentStart + CMTimeGetSeconds(segment.duration)
    let timeToEnd = segmentEnd - currentTime
    
    return (isPlaceholder: isPlaceholder, timeToNextBoundary: timeToEnd)
}
```

**Observer Preservation:**
- `replaceCurrentItem` doesn't require removing observers
- Existing KVO observations continue to work
- NotificationCenter observers remain valid
- Time observer remains active

---

### 5. Extension Checking Updates

**Location:** `Tapes/Playback/PlaybackEngine.swift` (line 435)

**Current:** Calls `install(composition: extended)` which creates new player

**Update:** Call `swapCompositionSeamlessly` instead

```swift
if let extended = try? await extensionManager.extendIfNeeded(...) {
    await swapCompositionSeamlessly(
        newComposition: extended,
        preservingTime: currentTime
    )
    TapesLog.player.info("PlaybackEngine: Composition extended seamlessly with \(completed.count) new assets")
}
```

---

## Benefits Analysis

### Advantages

1. **Simple Timeline Math**
   - No gaps = predictable durations
   - Position mapping is 1:1
   - Easier to test and validate

2. **Seamless Swaps**
   - No visible hiccup when assets load
   - User sees continuous playback
   - All assets eventually play

3. **Cleaner Skip Logic**
   - Timeline always complete
   - Skip handler just skips placeholder segments
   - No complex gap handling

4. **Better UX**
   - Black frames provide visual feedback (something loading)
   - Smooth transitions (fade to/from black)
   - No stuttering or jumps

### Trade-offs

1. **Placeholder Encoding Overhead**
   - ~50-100ms per unique placeholder
   - Mitigated by caching
   - One-time cost during initial build

2. **Memory (Minor)**
   - Placeholder assets in cache
   - ~1-2MB per cached placeholder
   - Acceptable given benefits

3. **Black Frame Display**
   - User sees black during skipped clips
   - Actually provides feedback (better than nothing)
   - Can be enhanced with "Loading..." overlay

---

## Implementation Checklist

### Phase 1: Placeholder Creation
- [ ] Add `createPlaceholderAsset()` method
- [ ] Implement placeholder caching
- [ ] Test placeholder creation performance
- [ ] Validate placeholder duration matches expectations

### Phase 2: Complete Timeline Building
- [ ] Update `buildPlayerItem()` to accept `allClips` parameter
- [ ] Create placeholder contexts for skipped clips
- [ ] Merge ready + placeholder contexts
- [ ] Update `makeTimelineWithSkips()` → `makeCompleteTimeline()`
- [ ] Ensure transitions work with placeholders

### Phase 3: Position Mapping
- [ ] Implement `mapTimeToNewTimeline()` helper
- [ ] Test mapping accuracy with various scenarios
- [ ] Validate edge cases (end of timeline, transitions)

### Phase 4: Seamless Swap
- [ ] Create `swapCompositionSeamlessly()` method
- [ ] Implement safe swap point detection
- [ ] Update `install()` → `installInitial()` for first install
- [ ] Test swap during playback (playing + paused)
- [ ] Validate observer preservation

### Phase 5: Integration
- [ ] Update `startExtensionChecking()` to use seamless swap
- [ ] Update `CompositionExtensionManager` to rebuild with placeholders
- [ ] Test end-to-end: initial load → background load → swap
- [ ] Performance testing (swap overhead)

### Phase 6: Edge Cases
- [ ] Swap while seeking
- [ ] Swap during transition
- [ ] Multiple swaps in quick succession
- [ ] Network failure during swap
- [ ] All clips initially missing (all placeholders)

---

## Testing Strategy

### Unit Tests
1. Placeholder creation (duration, size, format)
2. Timeline building with placeholders
3. Position mapping accuracy
4. Safe swap point detection

### Integration Tests
1. Initial build with placeholders
2. Background load → seamless swap
3. Multiple assets load simultaneously
4. Swap during various playback states

### Performance Tests
1. Placeholder encoding time
2. Swap operation overhead
3. Memory usage (cache size)
4. Timeline building time (with placeholders)

### Manual QA
1. Visual verification: No hiccups during swap
2. Position preservation: Seek accuracy maintained
3. Transitions: Smooth fade to/from black
4. All assets eventually play

---

## Risk Assessment

**Risk: Swap Timing**
- **Impact:** Medium
- **Mitigation:** Safe boundary detection, placeholder priority swap
- **Fallback:** Accept brief visual hiccup if safe boundary not found

**Risk: Position Mapping Accuracy**
- **Impact:** High
- **Mitigation:** Extensive testing, validate with various scenarios
- **Fallback:** Rebuild from current time (visible but acceptable)

**Risk: Placeholder Overhead**
- **Impact:** Low
- **Mitigation:** Caching, minimal encoding (2 frames)
- **Fallback:** Acceptable given UX benefits

---

## Next Steps

1. **Implement placeholder creation** (Phase 1)
2. **Update timeline building** (Phase 2)
3. **Add position mapping** (Phase 3)
4. **Implement seamless swap** (Phase 4)
5. **Integrate with extension checking** (Phase 5)
6. **Test and iterate** (Phase 6)

---

## Conclusion

Placeholder-based composition with seamless swaps provides:
- ✅ Zero visual impact when assets load
- ✅ All assets eventually play
- ✅ Simpler, more maintainable code
- ✅ Better user experience

The key insight: Placeholders ensure timeline positions map exactly between old and new compositions, enabling seamless `replaceCurrentItem` swaps with precise position preservation.

**Recommendation:** Proceed with implementation following the phased approach above.

