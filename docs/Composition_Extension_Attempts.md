# Composition Extension Fix Attempts Log

**Purpose:** Track all attempted fixes for composition extension issue where background-loaded clips are never added to the playback timeline.

**Status:** Active investigation - DO NOT repeat listed attempts

**Issue Description:**
- Background-loaded clips (9, 11, 12) load successfully but are never added to playback timeline
- `ExtendableCompositionStrategy.extendComposition()` always returns `nil` (not implemented)
- Playback jumps over missing clips: 8 → 10 (skips 9), then 10 → 13 (skips 11, 12)
- Extension checking runs every 2 seconds but extension never succeeds

**Root Cause:**
- `CompositionStrategy.swift:64-92` - `extendComposition()` method always returns `nil`
- Comment says "Phase 2 can implement proper merging later"
- Extension infrastructure exists (`CompositionExtensionManager`, `startExtensionChecking()`) but strategy is stub
- Timeline is built once with initial ready assets and never updated

**Evidence from Logs:**
```
Initial composition: ready: [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13]
BackgroundAssetService: Clip 9 loaded in background ✅
BackgroundAssetService: Clip 11 loaded in background ✅
BackgroundAssetService: Clip 12 loaded in background ✅
(No log: "PlaybackEngine: Composition extended") ❌
Playback: 8 → 10 (skips 9), 10 → 13 (skips 11, 12)
```

**Files Involved:**
- `Tapes/Playback/CompositionStrategy.swift` (extendComposition method, lines 64-92)
- `Tapes/Playback/CompositionExtensionManager.swift` (extendIfNeeded method)
- `Tapes/Playback/PlaybackEngine.swift` (startExtensionChecking method, lines 435-463)
- `Tapes/Playback/TapeCompositionBuilder.swift` (buildPlayerItem with skippedIndices)

**Related Issues:**
- Loading window timeout fix (commit `f1aa6ff`) - successfully prevented incorrect skipping
- This is the missing piece: extension infrastructure exists but strategy not implemented

---

## Attempt #1: [Not Yet Started]

**Date:** [TBD]  
**Commit:** [TBD]  
**Attempted By:** [TBD]

**What We Tried:**
- [TBD]

**Code Location:**
- [TBD]

**Did It Work?**
- [TBD]

**Why It Failed/Succeeded:**
- [TBD]

**Key Learning:**
- [TBD]

**Status:** Not Started

---

## Next Attempts To Consider (NOT YET TRIED)

### Option A: Rebuild Composition with All Assets (Simplest)
**Hypothesis:** When extension needed, rebuild entire composition with all available assets (existing + new).

**Approach:**
1. Get all existing segments from current composition
2. Get all new assets from background service
3. Combine existing + new assets
4. Rebuild composition using `builder.buildPlayerItem()`
5. Replace current composition

**Code Changes:**
- `ExtendableCompositionStrategy.extendComposition()`: Rebuild with all assets
- Need to reconstruct `ResolvedAsset` from existing segments OR cache them

**Risk:** Medium - Rebuilding entire composition may cause playback hiccup
**Effort:** M (2-3 hours)
**File:** `Tapes/Playback/CompositionStrategy.swift:64-92`

**Challenge:** Need to reconstruct `HybridAssetLoader.ResolvedAsset` from existing `Segment` objects

### Option B: Incremental Composition Extension (Complex but Smooth)
**Hypothesis:** Actually extend composition by inserting new segments into existing AVComposition without full rebuild.

**Approach:**
1. Get existing AVComposition from current composition
2. For each new asset, create new composition track segments
3. Insert segments at correct time positions (between existing segments)
4. Update video composition instructions
5. Update timeline metadata

**Code Changes:**
- `ExtendableCompositionStrategy.extendComposition()`: Actual AVComposition manipulation
- Need to handle transitions between old segments and new segments
- Need to handle transitions between new segments

**Risk:** High - Complex AVFoundation manipulation, edge cases with transitions
**Effort:** L (6-8 hours)
**File:** `Tapes/Playback/CompositionStrategy.swift:64-92`, potentially new file

**Challenge:** AVComposition manipulation is complex, especially with transitions and timing

### Option C: Cache ResolvedAssets During Initial Build
**Hypothesis:** Store `ResolvedAsset` instances alongside segments so we can reconstruct full asset list later.

**Approach:**
1. Modify `PlayerComposition` to store `resolvedAssets: [Int: HybridAssetLoader.ResolvedAsset]`
2. Store assets when building initial composition
3. During extension, merge existing cached assets + new assets
4. Rebuild with all assets (Option A but with proper asset access)

**Code Changes:**
- `TapeCompositionBuilder.PlayerComposition`: Add `resolvedAssets` property
- `TapeCompositionBuilder.buildPlayerItem()`: Store assets in composition
- `ExtendableCompositionStrategy.extendComposition()`: Use cached assets

**Risk:** Low - Minimal changes, reuses Option A approach
**Effort:** M (3-4 hours)
**File:** Multiple files

**Challenge:** Need to modify `PlayerComposition` structure

### Option D: Full Rebuild on Extension (Simple but May Cause Hiccup)
**Hypothesis:** When extension needed, get ALL assets (existing + background loaded) and rebuild from scratch.

**Approach:**
1. Get existing segments (indices)
2. Get all background-loaded assets
3. Get all initially ready assets (need to cache or reconstruct)
4. Combine and sort by index
5. Full rebuild with `builder.buildPlayerItem()`
6. Install new composition (may cause brief pause)

**Code Changes:**
- `ExtendableCompositionStrategy.extendComposition()`: Full rebuild
- May need to cache initial assets or get from background service

**Risk:** Medium - Brief playback pause during rebuild
**Effort:** S (1-2 hours)
**File:** `Tapes/Playback/CompositionStrategy.swift:64-92`

**Challenge:** How to get existing assets? Need to cache or store in composition

### Option E: Store Asset Map in PlaybackEngine
**Hypothesis:** PlaybackEngine maintains map of all resolved assets (index → ResolvedAsset) for extension use.

**Approach:**
1. Store `allResolvedAssets: [Int: HybridAssetLoader.ResolvedAsset]` in PlaybackEngine
2. Update map when initial assets ready and when background assets ready
3. During extension, get all assets from map and rebuild

**Code Changes:**
- `PlaybackEngine`: Add `allResolvedAssets` property
- Update map in `prepare()` and when background assets complete
- `ExtendableCompositionStrategy.extendComposition()`: Get all from engine

**Risk:** Low - Centralised asset tracking
**Effort:** M (2-3 hours)
**File:** `Tapes/Playback/PlaybackEngine.swift`, `CompositionStrategy.swift`

**Challenge:** Need to pass engine or asset map to strategy

---

## Checklist Before Each Attempt

- [ ] Check this list - has this approach been tried?
- [ ] Review how timeline handles skipped clips
- [ ] Understand segment structure and asset relationships
- [ ] Test with tape having 14+ clips where 3+ load in background
- [ ] Verify extension happens during playback
- [ ] Verify no playback hiccup or jump
- [ ] Verify all clips appear in playback
- [ ] Document attempt in this file
- [ ] Commit with clear message
- [ ] If fails, revert immediately and document why

---

**Last Updated:** [Current Date]  
**Current Status:** Issue identified - composition extension not implemented. Ready to start attempts.

**Relationship to Other Fixes:**
- **Loading Window Timeout (commit `f1aa6ff`):** ✅ Fixed - prevents incorrect skipping
- **Composition Extension (this issue):** ❌ Not implemented - this tracker for fixing it

**Key Insight:**
The timeout fix successfully prevented clips from being marked as skipped. However, clips that aren't ready initially need to be added via extension when they load. The extension infrastructure exists but the strategy is a stub returning `nil`.

