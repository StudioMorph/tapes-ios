# Loading Window Timeout Fix Attempts Log

**Purpose:** Track all attempted fixes for loading window timeout issue where clips are incorrectly marked as skipped before they can start loading.

**Status:** Active investigation - DO NOT repeat listed attempts

**Issue Description:**
- 15s loading window is meant to load as many assets as possible, then start playback
- Remaining assets should continue loading in background
- Assets should only be skipped if they fail to resolve by the time playback reaches them
- **Current Bug:** Sequential queue blocks waiting for in-progress loads, causing later clips to be marked as skipped before they even start loading

**Root Cause (Analysis):**
- `loadSequentialQueue()` waits for each asset to complete (`await result` on line 332)
- When deadline expires, loop continues waiting for in-progress loads
- Clips that could start are never checked because loop is blocked
- `loadingAssets` array is never populated (line 123 created but unused)
- Clips 11 & 12 marked as `.skipped(.timeout)` before they start loading

**Evidence from Logs:**
```
HybridAssetLoader: Queues completed in 16.25s (fast: 0, sequential: 12, cpu: 2)
HybridAssetLoader: Window expired, skipping remaining Photos assets
PlaybackEngine: Clip 11 skipped: timeout
PlaybackEngine: Clip 12 skipped: timeout
BackgroundAssetService: Enqueued 2 assets
BackgroundAssetService: Clip 11 loaded in background
BackgroundAssetService: Clip 12 loaded in background
```

**Files Involved:**
- `Tapes/Playback/HybridAssetLoader.swift` (loadSequentialQueue method, lines 312-345)
- `Tapes/Playback/PlaybackEngine.swift` (startBackgroundLoading method, lines 409-433)

---

## Attempt #1: Early Return on Deadline with Task Tracking (Option B)

**Date:** [Current Date]  
**Commit:** [Will be added after implementation]  
**Attempted By:** Loading window timeout fix

**What We Tried:**
- Return immediately from `loadSequentialQueue()` when deadline expires
- Don't block waiting for in-progress loads to complete
- Track which tasks have started loading vs never started
- Populate `loadingAssets` array with clip indices that started but haven't finished
- Mark only clips that never started as `.skipped(.timeout)`
- Let background service handle both skipped AND loading assets

**Approach:**
1. Before starting each clip, check deadline (keep existing check)
2. If deadline expired, return immediately with current results
3. Track started tasks separately from completed results
4. When returning, include in-progress clips in `loadingAssets` array
5. Background service already handles non-ready clips, so it will pick up both

**Code Location:**
- `Tapes/Playback/HybridAssetLoader.swift:312-345` (loadSequentialQueue method)

**Did It Work?**
- [TBD - will be marked after testing]

**Why It Failed/Succeeded:**
- [TBD]

**Key Learning:**
- [TBD]

**Status:** In Progress - Implementation starting

---

## Next Attempts To Consider (NOT YET TRIED)

### Option A: Non-Blocking Sequential Queue with Task Tracking
**Hypothesis:** Don't wait for in-progress loads to complete. Start all loads, track tasks, return when deadline expires with what's ready.

**Approach:**
1. Create tasks for all sequential clips at once (or in batches)
2. Track tasks in array
3. When deadline expires, collect ready results immediately
4. Return in-progress tasks in `loadingAssets` array
5. Let in-progress tasks complete in background (don't await them in window)

**Code Changes:**
- `loadSequentialQueue()`: Create tasks for all clips, track them
- Don't `await` tasks one-by-one in loop
- Check deadline, collect ready results, return remaining as `loadingAssets`

**Risk:** Medium - Need to ensure tasks continue in background without blocking
**Effort:** M (3-4 hours)
**File:** `Tapes/Playback/HybridAssetLoader.swift:312-345`

### Option B: Early Return on Deadline with Background Continuation
**Hypothesis:** Return from `loadWindow()` immediately when deadline expires, leave active tasks running in background.

**Approach:**
1. Check deadline before each clip start (keep current check)
2. If deadline expired, return immediately with:
   - Ready assets (completed)
   - Loading assets (task indices that started but not finished)
   - Skipped assets (never started)
3. Let background service pick up both skipped AND loading assets

**Code Changes:**
- `loadSequentialQueue()`: Return immediately when deadline expires
- Track which tasks have started vs not started
- Populate `loadingAssets` with in-progress task indices

**Risk:** Low - Simpler change, matches intended design
**Effort:** S (1-2 hours)
**File:** `Tapes/Playback/HybridAssetLoader.swift:312-345`

### Option C: Parallel Sequential Queue (Contradictory Name but Faster)
**Hypothesis:** Load sequential queue assets in parallel with limit (e.g., max 3 concurrent), not truly sequential.

**Approach:**
1. Use `withTaskGroup` with limited concurrency for sequential queue
2. Track start times, return when deadline expires
3. More assets start simultaneously, less blocking

**Risk:** High - May exhaust Photos API (the original reason for sequential loading)
**Effort:** M (2-3 hours)
**File:** `Tapes/Playback/HybridAssetLoader.swift:312-345`

### Option D: Reduce Overlap Delay
**Hypothesis:** Overlap delay (1.5s) might be too conservative. Reduce to 0.5-1.0s to fit more clips in window.

**Approach:**
- Change `overlapDelay` from 1.5s to 1.0s or 0.8s
- Still prevents Photos API exhaustion but allows more clips to start

**Risk:** Medium - May cause Photos API exhaustion if too aggressive
**Effort:** S (5 minutes - just change constant)
**File:** `Tapes/Playback/HybridAssetLoader.swift:19`

### Option E: Dynamic Window Duration Based on Queue Size
**Hypothesis:** Calculate window duration based on number of assets to load, ensuring all can start.

**Approach:**
- Calculate: `windowDuration = max(15.0, photosClips.count * 1.5 + 5.0)`
- For 12 clips: `12 * 1.5 + 5 = 23s` window
- Ensures all clips get chance to start

**Risk:** Low - Still respects maximum window, just adapts
**Effort:** S (10 minutes)
**File:** `Tapes/Playback/HybridAssetLoader.swift:67-69`

**Note:** This contradicts user's clarification that window should NOT load all assets, but ensures all get chance to START.

---

## Checklist Before Each Attempt

- [ ] Check this list - has this approach been tried?
- [ ] Review diagnostic logs for affected clips
- [ ] Understand current sequential queue blocking behavior
- [ ] Test with tape having 12+ Photos assets
- [ ] Verify ready clips start playback correctly
- [ ] Verify skipped clips load in background
- [ ] Verify loading clips continue after window expires
- [ ] Document attempt in this file
- [ ] Commit with clear message
- [ ] If fails, revert immediately and document why

---

**Last Updated:** [Current Date]  
**Current Status:** Attempt #1 in progress - implementing non-blocking sequential queue

