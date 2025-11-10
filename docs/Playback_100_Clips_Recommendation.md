# Playback for 100+ Clips - Recommended Approach

**Requirements:**
- ✅ Playback starts in 15 seconds or less
- ✅ No visible skipping when composition rebuilds happen
- ✅ Support 100+ clips (iCloud-heavy tapes)

**Status:** Recommendation - No Code Yet

---

## Recommended Approach: Placeholder-Based with Smart Batch Rebuilds

### Core Strategy

**1. Placeholder-Based Timeline (Immediate Playback)**
- Build complete timeline upfront with placeholder assets for ALL clips
- Playback starts in <1 second (not 15s - much faster!)
- All clips present in timeline from start (no gaps)

**2. Optimized Concurrent Loading (Maximum Resolution)**
- Load 3-4 Photos assets concurrently (vs current 1 sequential)
- Use `.fastFormat` delivery mode (2-3× faster)
- Reduce overlap delay to 0.5s (from 1.5s)
- Result: 15-30 clips resolved in 15s window

**3. Smart Batch Rebuilds (Invisible Swaps)**
- Batch resolved clips: Wait for 3-5 clips OR 2 seconds
- Rebuild only at safe boundaries:
  - During placeholder segments (black frame - invisible)
  - At transition boundaries (brief, acceptable)
  - While paused (seamless)
- Result: 10-20 swaps total (vs 100), all invisible

**4. Background Continuation**
- Continue loading remaining 70-85 clips in background
- Rebuilds happen automatically as clips resolve
- All clips eventually play (zero skipped)

---

## Why This Approach Works

### 1. Immediate Playback (<1s, not 15s)

**Placeholder Timeline:**
- Build complete timeline with placeholders for all 100 clips
- Timeline structure: Identical to final (same segments, same timing)
- Placeholder assets: Black video (2 frames, instant creation)
- **Result:** Playback starts immediately (<1s)

**vs Current Approach:**
- Current: Wait 15s for some assets, start with gaps
- Placeholder: Start immediately, fill gaps as assets load

### 2. No Visible Skipping

**Smart Swap Boundaries:**
- **During Placeholder:** Swap is invisible (black frame → black frame)
- **During Transition:** Brief pause (~0.1s) at natural boundary (acceptable)
- **While Paused:** Completely seamless (no visual change)

**Batching Strategy:**
- Don't rebuild for every single clip (would cause 100 swaps)
- Batch 3-5 clips together (reduces to 20-30 swaps)
- Only swap when at safe boundary (reduces visible swaps to 0-5)

**Position Mapping:**
- Placeholders ensure 1:1 timeline mapping
- Same clip index = same timeline position
- Swap preserves exact playback position (no jump)

### 3. Maximum Asset Resolution

**Optimized Loading:**
- 3-4 concurrent (vs 1 sequential) = 3-4× more clips started
- `.fastFormat` = 2-3× faster downloads
- 0.5s overlap (vs 1.5s) = 3× more clips in window
- **Result:** 15-30 clips resolved in 15s (vs current ~10)

**Background Continuation:**
- Remaining 70-85 clips continue loading
- Rebuilds happen automatically
- No user waiting required

---

## Technical Architecture

### Phase 1: Initial Build (Immediate)

```
1. Create placeholder assets (cached, instant)
2. Build complete timeline with ALL clips:
   - Ready assets: Use real AVAsset
   - Missing assets: Use placeholder AVAsset
3. Timeline structure: Identical to final (same segments, transitions)
4. Install composition (<1s total)
5. Start playback immediately
```

**Timeline Example:**
```
Clips: 0(ready), 1(loading), 2(ready), 3(loading), 4(loading)...
Timeline:
  - Segment 0: Clip 0 (real) @ 0-5s
  - Segment 1: Clip 1 (placeholder) @ 5-8s
  - Segment 2: Clip 2 (real) @ 8-13s
  - Segment 3: Clip 3 (placeholder) @ 13-16s
  - Segment 4: Clip 4 (placeholder) @ 16-19s
```

### Phase 2: Background Loading (Optimized)

```
1. Load 3-4 clips concurrently (Photos API limit)
2. Use .fastFormat for faster returns
3. Continue until all 100 clips resolved
4. Track resolved clips in background service
```

**Loading Queue:**
```
Window (15s): Resolve 15-30 clips
Background: Continue resolving 70-85 clips
Priority: Load clips that come sooner first
```

### Phase 3: Smart Rebuilds (Invisible)

```
1. Collect resolved clips (batch 3-5 or 2s timeout)
2. Check current playback position
3. If at safe boundary:
   - Rebuild composition with new assets
   - Swap using replaceCurrentItem
   - Preserve exact playback position
4. If not at safe boundary:
   - Queue for next safe boundary
   - Wait for placeholder segment or transition
```

**Safe Boundaries:**
- **Placeholder segments:** Black frame - swap invisible
- **Transition boundaries:** Brief pause acceptable
- **Paused state:** Completely seamless

---

## Rebuild Strategy Details

### When to Rebuild?

**Immediate (No Delay):**
- Current playback is in placeholder segment (black frame)
- Playback is paused
- First 3-5 clips resolve (high priority)

**Batched (Wait for Safe Boundary):**
- Current playback is in real clip
- Wait for next placeholder segment or transition
- Batch multiple clips together (3-5 at once)

**Never Rebuild:**
- During active playback of real clip (would cause visible skip)
- If playback is near end (<5s remaining)

### Rebuild Frequency

**Scenario: 100 Clips**
- Initial: 15-30 clips ready (15s window)
- Background: 70-85 clips resolve over time
- Rebuilds: ~20-30 total (batched)
- Visible swaps: 0-5 (only at safe boundaries)

**vs Current Approach:**
- Current: 100 swaps (one per clip) = visible skipping
- Recommended: 20-30 swaps (batched) = 0-5 visible

---

## Performance Characteristics

### Timeline Build Time

**Placeholder Creation:**
- Cached placeholders: Instant (0.001s per placeholder)
- 100 placeholders: ~0.1s total
- Reusable: Same placeholder asset per (size, duration)

**Timeline Building:**
- Structure computation: ~0.1s (same as current)
- Asset insertion: ~0.01s per asset
- 100 assets: ~1s total
- **Total: ~1.1s** (vs current 15s wait)

### Rebuild Time

**Per Rebuild:**
- Timeline structure: Reuse (no recompute) = 0s
- Asset replacement: ~0.01s per asset
- 5 assets replaced: ~0.05s
- Video composition: Recalculate instructions = ~0.1s
- Swap: replaceCurrentItem + seek = ~0.1s
- **Total: ~0.25s per rebuild**

**Frequency:**
- 20-30 rebuilds over playback duration
- Most during early playback (first 1-2 minutes)
- Taper off as remaining clips are further ahead

### Visual Impact

**Swap During Placeholder:**
- Visual: None (black frame → black frame)
- Audio: None (no audio in placeholders)
- Duration: ~0.1s (imperceptible)

**Swap During Transition:**
- Visual: Brief pause (~0.1s) at natural boundary
- Acceptable: Transitions already have brief pauses
- Duration: ~0.1s (matches transition pause)

**Swap While Paused:**
- Visual: None (no playback = no visible change)
- Duration: ~0.1s (imperceptible)

---

## Comparison Matrix

| Approach | Playback Start | Visible Skips | Clips Resolved (15s) | Complexity |
|----------|---------------|---------------|----------------------|------------|
| **Current Sequential** | 15s | None (gaps) | ~10 clips | Low |
| **Optimized Concurrent** | 15s | None (gaps) | ~30 clips | Medium |
| **Placeholder Only** | <1s | 0-5 (batched) | ~15 clips | Medium |
| **Recommended Hybrid** | <1s | 0-5 (batched) | ~30 clips | High |

---

## Risk Assessment

### Risk 1: Placeholder Creation Overhead
- **Impact:** Low
- **Mitigation:** Cache placeholders by (size, duration)
- **Reality:** 100 placeholders = ~0.1s (negligible)

### Risk 2: Rebuild Frequency Too High
- **Impact:** Medium
- **Mitigation:** Smart batching (3-5 clips or 2s timeout)
- **Reality:** 20-30 rebuilds over 100-clip playback (manageable)

### Risk 3: Visible Swap During Real Clip
- **Impact:** High (user requirement)
- **Mitigation:** Only swap at safe boundaries (placeholders, transitions, pause)
- **Reality:** 0-5 visible swaps (only if user seeks during rebuild)

### Risk 4: Photos API Exhaustion
- **Impact:** Medium
- **Mitigation:** Limit to 3-4 concurrent (tested safe limit)
- **Reality:** Previous attempts showed 3-4 is safe

### Risk 5: Memory from 100 Placeholders
- **Impact:** Low
- **Mitigation:** Placeholders are tiny (2 frames, minimal encoding)
- **Reality:** 100 placeholders ≈ 5-10MB (negligible)

---

## Implementation Phases

### Phase 1: Placeholder Infrastructure (Foundation)
1. Create placeholder asset factory (black video, cached)
2. Modify `buildPlayerItem` to accept placeholder assets
3. Build complete timeline with placeholders
4. Test: Playback starts immediately

**Effort:** M (4-5 hours)  
**Risk:** Low  
**Benefit:** Immediate playback

### Phase 2: Smart Rebuild Logic (Seamless Swaps)
1. Implement `swapCompositionSeamlessly` method
2. Add safe boundary detection
3. Implement batching logic (3-5 clips or 2s timeout)
4. Test: No visible skipping during rebuilds

**Effort:** M (4-5 hours)  
**Risk:** Medium  
**Benefit:** Invisible swaps

### Phase 3: Optimized Loading (Maximum Resolution)
1. Increase concurrency to 3-4 (from 1)
2. Change delivery mode to `.fastFormat`
3. Reduce overlap delay to 0.5s (from 1.5s)
4. Test: More clips resolved in 15s window

**Effort:** M (3-4 hours)  
**Risk:** Medium (Photos API limits)  
**Benefit:** 3× more clips resolved

### Phase 4: Background Integration (Complete)
1. Integrate background service with rebuild logic
2. Test with 100-clip tape
3. Verify all clips eventually play
4. Performance tuning

**Effort:** M (3-4 hours)  
**Risk:** Low  
**Benefit:** Complete solution

**Total Effort:** L (14-18 hours across 4 phases)

---

## Testing Strategy

### Test Case 1: 100 iCloud Videos (All Remote)
- **Measure:** Playback start time (target: <1s)
- **Measure:** Clips resolved in 15s (target: 15-30)
- **Verify:** No visible skipping during rebuilds
- **Verify:** All 100 clips eventually play

### Test Case 2: Mixed (50 Local + 50 iCloud)
- **Measure:** Playback start time (target: <1s)
- **Verify:** All locals play immediately
- **Verify:** iCloud clips appear as they load

### Test Case 3: Network Conditions
- **Fast Wi‑Fi:** Verify maximum resolution
- **Slow Wi‑Fi:** Verify graceful degradation
- **Cellular:** Verify reduced concurrency

### Test Case 4: Rebuild Boundaries
- **During Placeholder:** Verify invisible swap
- **During Real Clip:** Verify swap waits for boundary
- **While Paused:** Verify seamless swap

---

## Recommendation Summary

**Recommended Approach:** **Placeholder-Based with Smart Batch Rebuilds + Optimized Loading**

**Why This Works:**
1. ✅ **Playback starts in <1s** (not 15s) - Placeholders enable immediate start
2. ✅ **No visible skipping** - Smart batching + safe boundaries = 0-5 visible swaps
3. ✅ **100+ clips supported** - Complete timeline from start, all clips eventually play
4. ✅ **Maximum resolution** - 15-30 clips in 15s (vs current ~10)

**Key Innovations:**
- Placeholders: Complete timeline = immediate playback
- Smart batching: 20-30 rebuilds (vs 100) = minimal visible swaps
- Safe boundaries: Only swap when invisible = zero user-visible skips
- Optimized loading: 3-4 concurrent + fast format = maximum clips resolved

**Trade-offs:**
- **Complexity:** Higher (4 phases, ~14-18 hours)
- **Memory:** Slightly higher (placeholder assets, ~5-10MB)
- **Benefit:** Massive improvement in UX (immediate playback, no skipping)

---

## Alternative: Simpler Incremental Approach

If complexity is a concern, we could do **Phase 1 + Phase 3** first:

1. **Placeholder Infrastructure** (Phase 1)
   - Immediate playback (<1s)
   - All clips in timeline from start
   - Rebuilds happen (may have some visible swaps initially)

2. **Optimized Loading** (Phase 3)
   - More clips resolved in 15s
   - Background continuation works

3. **Add Smart Rebuilds Later** (Phase 2)
   - Refine rebuild timing
   - Eliminate visible swaps

**This gives:**
- Immediate playback ✅
- All clips eventually play ✅
- Some visible swaps initially (acceptable for first version)
- Can refine later

**Effort:** M (7-9 hours)  
**Risk:** Lower (incremental)

---

## Final Recommendation

**Go with Full Hybrid Approach:**
- Best user experience (immediate playback, no visible skipping)
- Solves all requirements
- Worth the complexity for 100+ clip tapes

**Start with Phase 1 + Phase 3:**
- Get immediate playback working
- Get optimized loading working
- Add smart rebuilds (Phase 2) as refinement

This gives you:
- Immediate playback ✅
- Maximum clips resolved ✅
- Some visible swaps initially (acceptable)
- Can refine to zero visible swaps later

