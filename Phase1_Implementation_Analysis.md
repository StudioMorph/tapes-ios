# Phase 1 Implementation Analysis
## Root Cause Analysis of Playback Issues

---

## User's Observations

1. **Long wait (8-9 seconds)** before auto-start
2. **Video autostarts with only one asset** (partial composition)
3. **Other assets start loading AFTER playback begins**
4. **Playback keeps jumping back to first clip** when new compositions are installed
5. **No "Loading Tape" overlay** during the wait

---

## Root Cause Analysis

### Problem 1: We're Implementing Phase 2 Behavior in Phase 1

**What the Roadmap Says (Phase 1)**:
> **5. CompositionBuilder (2D Transitions Only)**
> - ✅ **Single composition strategy (all clips in one)**
> - ❌ Segment-based or queue-based strategies (defer to Phase 2)

**What We Actually Implemented**:
- Progressive/partial compositions (warmup with 5 clips, then rebuild with more)
- `onProgress` callbacks that rebuild the composition as more clips load
- This is **Phase 2 behavior** (Segment-based strategy)

**Why This Causes Jumping**:
1. Warmup builds composition with first 5 clips → installs → playback starts
2. Continuation resolves clip 6 → rebuilds ENTIRE composition (0-6) → `replace()` called
3. New composition has different timeline → preserving time doesn't work correctly
4. Playback jumps back to start when new playerItem is installed

### Problem 2: Sequential Loading During Warmup is Too Slow

**Current Flow**:
```
performWarmup():
  - Sequentially resolves clips 0-4 (one at a time)
  - Each clip: resolveClipContext() → can take 1-2 seconds per clip
  - Total: 5-10 seconds just for warmup
  - THEN builds composition
  - THEN installs player
```

**Why This is Wrong**:
- Phase 1 roadmap says "Background Prefetch" and "Next-Clip Pipeline"
- But we're doing sequential resolution during warmup (blocking)
- Should load ALL clips in parallel, then build ONE composition

### Problem 3: Composition Rebuilding During Playback

**What Happens**:
```swift
onProgress: { result in
    let current = engineRef.player?.currentTime()
    engineRef.replace(with: result.composition, autoplay: engineRef.isPlaying, preserveTime: current)
}
```

**The Issue**:
- `buildResult()` creates a NEW composition with subset of clips
- New timeline has different total duration
- `preserveTime` seeks to absolute time, but timeline changed
- Example: Was at 10s in 5-clip composition, new composition has clips 0-6, but timeline offsets are different → jump

### Problem 4: Warmup Window Size vs Actual Need

**Current**: `warmupWindowSize = 5`, `warmupTimeout = 15s`

**Reality**:
- If clips resolve sequentially, 5 clips × 2s each = 10s minimum
- But we also build the composition (another 1-2s)
- Total: 11-12s before playback starts
- User sees: 8-9s wait (matches this math)

**What Should Happen (Phase 1)**:
- Load ALL clips in parallel (not sequentially)
- Build ONE composition with all ready clips
- If some clips timeout, skip them, but build with what's available
- Don't rebuild during playback

---

## Comparison: What Phase 1 Should Be vs What We Built

### Phase 1 Intent (From Roadmap):
1. **Fast startup**: ≤ 500ms for local, ≤ 2s for iCloud (p95)
2. **Single composition**: All clips in one composition
3. **Background prefetch**: Assets ready before needed
4. **Next-clip pipeline**: Always 1-2 clips ahead (for seamless playback)

### What We Actually Built:
1. **Slow startup**: 8-9s sequential warmup
2. **Progressive compositions**: Rebuild as clips load (Phase 2 behavior)
3. **Background prefetch**: ✅ Working (BackgroundAssetService)
4. **Composition swapping**: Replacing player items during playback (causes jumps)

---

## The Core Issue: Architecture Mismatch

**We built a "progressive segment-based player" when Phase 1 should be "simple single-composition player"**

### Correct Phase 1 Flow Should Be:
```
1. Show "Loading Tape" immediately
2. Load ALL clips in parallel (with timeouts)
3. Build ONE composition with all ready clips (or skip failed ones)
4. Install player → autoplay
5. Continue prefetching remaining clips in background (for future playback if needed)
6. DON'T rebuild composition during playback
```

### What We Actually Built:
```
1. Show "Loading Tape" (but not immediately - state set late)
2. Sequentially load first 5 clips (slow)
3. Build partial composition with 5 clips
4. Install → autoplay
5. Continue loading more clips sequentially
6. Rebuild composition each time new clip ready (causes jumps)
```

---

## Specific Code Issues

### Issue 1: `performContinuation()` Rebuilds Composition
**Location**: `PlaybackCoordinator.swift:215-240`

**Problem**: 
- Every time a new clip resolves, we call `buildResult()` and `onProgress()`
- This rebuilds the ENTIRE composition from scratch
- Replaces player item mid-playback → jump

**Fix**: Should only build composition ONCE after all clips loaded (or timeout)

### Issue 2: Sequential Resolution in Warmup
**Location**: `PlaybackCoordinator.swift:160-171`

**Problem**:
- `for (index, clip) in window.enumerated()` loops sequentially
- Each `await resolveClip()` blocks until complete
- Should resolve in parallel

**Fix**: Use `TaskGroup` to resolve all warmup clips in parallel

### Issue 3: `preserveTime` Doesn't Work When Timeline Changes
**Location**: `PlayerEngine.swift:144-159`

**Problem**:
- When new composition installed, timeline total duration changes
- Absolute time preservation doesn't account for timeline differences
- Should preserve clip index + offset within clip, not absolute time

**Fix**: Don't replace compositions during playback, OR preserve clip index + relative offset

---

## What Should Be Phase 2 vs Phase 1

### Phase 1 (What We Should Have):
- ✅ Load all clips upfront (parallel, with timeouts)
- ✅ Build ONE composition with all ready clips
- ✅ Play entire composition
- ✅ Background prefetch for seamless playback
- ❌ NO composition rebuilding during playback
- ❌ NO progressive/partial compositions

### Phase 2 (What We Accidentally Built):
- Progressive segment-based compositions
- Rebuilding composition as clips load
- Timeline preservation during composition swaps
- This is SegmentCompositionStrategy territory

---

## Recommendations

### Option A: Fix Phase 1 to Match Intent (Recommended)
1. Remove `onProgress` callbacks that rebuild composition
2. Make warmup resolve ALL clips in parallel (not just first 5)
3. Build ONE composition after all clips loaded (or timeout reached)
4. Don't rebuild during playback
5. Keep background prefetch for future use

**Pros**: Matches Phase 1 intent, simpler, faster startup
**Cons**: If clips timeout, playback starts with fewer clips (acceptable for Phase 1)

### Option B: Move Current Implementation to Phase 2
1. Keep current progressive composition code
2. Add proper timeline preservation (clip index + offset)
3. Label it as Phase 2
4. Rebuild Phase 1 as simple single-composition

**Pros**: Current code isn't wasted
**Cons**: More work, delays Phase 1 completion

---

## Honest Assessment

**Yes, we got ahead of ourselves.** The current implementation is more sophisticated than Phase 1 needs to be. Phase 1 should be:
- Simple
- Fast
- Reliable
- "Load → Build → Play" (not "Load → Build → Play → Rebuild → Play")

The progressive composition approach is Phase 2 territory and requires:
- Proper timeline preservation (clip index tracking)
- Segment management
- Queue-based player for large tapes

**My Recommendation**: Option A - Simplify to match Phase 1 intent. The current approach is causing the jumping issue and is over-engineered for Phase 1's scope.

---

## Next Steps (After Decision)

If Option A:
1. Modify `performWarmup()` to resolve ALL clips in parallel
2. Remove `onProgress` callbacks (keep only `onWarmupReady` and `onCompletion`)
3. Build composition once after all clips loaded (or timeout)
4. Keep background prefetch for future enhancements

If Option B:
1. Implement proper timeline preservation (preserve clip index, not absolute time)
2. Move current code behind Phase 2 flag
3. Rebuild Phase 1 simpler

---

**Document Created**: During Phase 1 implementation review  
**Status**: Analysis complete, awaiting decision

