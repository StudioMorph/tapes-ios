# Video Misalignment Fix Attempts Log

**Purpose:** Track all attempted fixes to prevent repeating failed approaches and document learnings.

**Status:** Active investigation - DO NOT repeat listed attempts

---

## Attempt #1: Reset Translation Before Scaling

**Date:** [Current Date]  
**Commit:** [Before revert] → [After revert]  
**Attempted By:** Diagnostic investigation

**What We Tried:**
- Reset `tx` and `ty` to 0 before scaling the transform
- Extract only rotation/scaling matrix from `preferredTransform`
- Apply scaling to rotation/scaling matrix only
- Apply centring translation separately (not scaled)

**Code Location:**
- `TapeCompositionBuilder.swift:1086-1103` (baseTransform method)
- `PlaybackEngine.swift:688-700` (computeFinalTransform method)

**Did It Work?**
❌ **NO - Complete failure**

**Why It Failed:**
- Reset `tx`/`ty` to 0 broke rotation transforms entirely
- All videos stopped showing (only audio worked)
- The translation components (`tx`, `ty`) in `preferredTransform` are **integral to the rotation matrix itself**, not just positional offsets
- Removing translation before scaling destroyed the rotation's coordinate space anchor points
- Even previously working clips (1, 2, 6, 7, 8, 9 with 90° rotation) broke

**Key Learning:**
The `preferredTransform` translation is **part of the rotation transform**, not separate. For rotations:
- 90° rotation: `tx:1080.0, ty:0.0` — needed to position rotated frame correctly
- 180° rotation: `tx:1920.0, ty:1080.0` — needed to position rotated frame correctly

**Root Cause Hypothesis Updated:**
The issue is NOT with resetting translation. The issue is likely:
- How the scaled translation interacts with the centring calculation
- OR the order of operations (scale first, then translate vs translate first, then scale)
- OR the coordinate space in which translations are applied (scaled vs unscaled space)

**Status:** Reverted — all videos working again (with original misalignment on clips 0, 3, 4, 5)

---

## Attempt #2: Option A - Match TapeExporter Transform Approach ✅ SUCCESS

**Date:** [Current Date]  
**Commit:** `1d034f9`  
**Attempted By:** Systematic fix attempt

**What We Tried:**
- Changed `scaledBy()` to `concatenating()` for scale transform (matches TapeExporter.swift:36)
- Changed `translatedBy()` to `concatenating()` for translation transform (matches TapeExporter.swift:39)
- Removed division by scale on translation (matches TapeExporter exactly)
- Applied same fix to both `baseTransform()` and diagnostic `computeFinalTransform()`

**Code Location:**
- `TapeCompositionBuilder.swift:1086-1093` (baseTransform method)
- `PlaybackEngine.swift:688-696` (computeFinalTransform method)

**Did It Work?**
✅ **YES - Complete success**

**Why It Worked:**
- `concatenating()` handles transform composition differently than `scaledBy()` + `translatedBy()`
- The division by scale was incorrect - translations should be in render coordinate space, not scaled space
- TapeExporter already had the correct approach; playback code was using incorrect method
- All misaligned clips (0, 3, 4, 5) now render correctly
- All previously working clips (1, 2, 6, 7, 8, 9) still work correctly

**Key Learning:**
- When composing transforms with rotation + scale + translation, `concatenating()` is more reliable than chaining `scaledBy()` + `translatedBy()`
- Transform translations should be in the final render coordinate space, not scaled intermediate space
- Always check existing working code (TapeExporter) for proven patterns before inventing new approaches

**Status:** ✅ RESOLVED - All videos now render correctly centred

---

## Pattern Analysis (From Diagnostics)

### Clips That Misalign (0, 3, 4, 5):
- **Clips 0 & 3:** 180° rotation `[a:-1, b:0, c:0, d:-1, tx:1920.0, ty:1080.0]`
  - After scaling (0.562): `finalTransform` shows `tx:1920.0 ty:423.7`
  - Translation `ty` is being modified incorrectly
  - `displaySize=1920x1080` (landscape) → `renderSize=1080x1920` (portrait)
  
- **Clip 4:** Unusual aspect ratio `naturalSize=888x1920`
  - `preferredTransform` identity `[a:1, b:0, c:0, d:1, tx:0, ty:0]`
  - `finalTransform` shows `tx:96.0 ty:0.0` (centring offset)
  - Narrow width (888) vs render width (1080) requires horizontal centring

- **Clip 5:** 180° rotation (same as 0 & 3)

### Clips That Work (1, 2, 6, 7, 8, 9):
- All have 90° rotation `[a:0, b:1, c:-1, d:0, tx:1080.0, ty:0.0]`
- `displaySize=1080x1920` matches `renderSize=1080x1920` perfectly
- No scaling needed (`scale ≈ 1.0`)
- `finalTransform` equals `preferredTransform` (no modification)

### Current Transform Calculation (Line 1090):
```swift
transform = transform.translatedBy(x: translatedX / scale, y: translatedY / scale)
```
**Question:** Why divide by scale? This applies translation in the **scaled coordinate space**, which may be incorrect.

---

## Next Attempts To Consider (NOT YET TRIED)

### Option A: Use Concatenation Instead of scaledBy (Match TapeExporter)
**Evidence:** `TapeExporter.swift:36-39` uses `concatenating()` instead of `scaledBy()` and does NOT divide translation by scale
```swift
var t = preferredTransform
t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
let x = (renderWidth - absWidth * scale) / 2
let y = (renderHeight - absHeight * scale) / 2
t = t.concatenating(CGAffineTransform(translationX: x, y: y))  // NO division by scale
```
**Hypothesis:** `concatenating()` may handle transform composition differently than `scaledBy()` + `translatedBy()`
**Risk:** Low - TapeExporter presumably works for exports, but playback context may differ
**Effort:** S (1 hour)
**File:** `TapeCompositionBuilder.swift:1086-1091`

### Option B: Don't Divide Translation By Scale
**Hypothesis:** Centring translation should be in render coordinate space (final space), not scaled space
```swift
transform = transform.translatedBy(x: translatedX, y: translatedY)  // No division
```
**Mathematical Reasoning:** 
- `translatedX/Y` are calculated in render space: `(renderWidth - absWidth * scale) / 2`
- These values are already correct for render space (1080x1920)
- Dividing by scale converts them to scaled space, which is wrong if final output is render space
**Risk:** Medium - May break working clips if coordinate space assumption is wrong
**Effort:** S (1 hour)
**File:** `TapeCompositionBuilder.swift:1090`

### Option C: Scale Translation Separately and Compose Correctly
**Hypothesis:** Need to handle preferredTransform's translation in its original space, then convert to render space
**Approach:**
1. Apply scale to rotation/scaling matrix (a,b,c,d) only
2. Convert preferredTransform's translation (tx, ty) from natural space to render space
3. Add centring translation in render space
**Risk:** High - Complex coordinate space conversions
**Effort:** M (3-4 hours)
**File:** `TapeCompositionBuilder.swift:1060-1092`

### Option D: Special-Case 180° Rotations
**Evidence:** Only 180° rotations misalign; 90° rotations work perfectly
**Hypothesis:** 180° rotations require different transform composition
**Approach:** Detect 180° rotation (`a:-1, d:-1`) and use different centring logic
**Risk:** Medium - Fragile, doesn't fix clip 4 (unusual aspect ratio)
**Effort:** M (2-3 hours)
**File:** `TapeCompositionBuilder.swift:1060-1092`

### Option E: Fix Coordinate Space Issue - Translate in Correct Space
**Mathematical Analysis:**
- Current: `translatedBy(x: translatedX / scale, y: translatedY / scale)`
  - This applies translation in **scaled coordinate space**
  - For scale=0.562, dividing by scale makes translation ~1.78x larger
  - This might be correct if transforms are composed in scaled space
- Alternative: `translatedBy(x: translatedX, y: translatedY)` (no division)
  - This applies translation in **render coordinate space**
  - This might be correct if final output is render space

**Key Question:** What coordinate space does AVFoundation use for final rendering?
- If render space: Don't divide
- If scaled space: Divide (current approach, but broken)

**Risk:** Medium - Need to verify AVFoundation coordinate space
**Effort:** M (2-3 hours with testing)

### Option F: Investigate Actual Composition Instruction Transform
**Hypothesis:** The transform we compute might be correct, but there's another issue (VideoGravity, container size, etc.)
**Approach:** 
- Extract actual transform from `AVVideoCompositionLayerInstruction` at runtime
- Compare computed vs actual
- Check if VideoGravity is overriding our transform
**Risk:** Low - Diagnostic only, won't break anything
**Effort:** M (2-3 hours to add extraction code)
**File:** New diagnostic code in `PlaybackEngine`

### Option G: Apply Transform in Two Steps (Like Motion Effects)
**Evidence:** `apply(effect:to:renderSize:progress:)` line 822-825 uses a pattern:
1. Translate to center
2. Scale
3. Translate back
4. Translate with offset

**Approach:** Apply similar pattern for base transform:
1. Translate preferredTransform's result to origin
2. Apply our scale
3. Translate back + centring
**Risk:** Medium - Complex, but pattern exists elsewhere in codebase
**Effort:** M (3-4 hours)
**File:** `TapeCompositionBuilder.swift:1060-1092`

### Option H: Reverse-Engineer Working Transform
**Approach:**
- Manually calculate what the transform SHOULD be for clip 0 (180° rotation)
- Compare with what we're generating
- Identify the exact difference
- Fix only that difference
**Risk:** Low - Targeted fix
**Effort:** M (2-3 hours for math + implementation)

---

## Mathematical Analysis from Logs

### Clip 0 (Misaligned - 180°):
- `naturalSize`: 1920x1080
- `preferredTransform`: `[a:-1, b:0, c:0, d:-1, tx:1920, ty:1080]`
- `displaySize` after preferredTransform: 1920x1080 (landscape)
- `renderSize`: 1080x1920 (portrait)
- Scale needed: min(1080/1920, 1920/1080) = min(0.5625, 1.777) = **0.5625**
- Centring needed: X = (1080 - 1920*0.5625)/2 = (1080-1080)/2 = **0**
- Centring needed: Y = (1920 - 1080*0.5625)/2 = (1920-607.5)/2 = **656.25**
- Current finalTransform: `tx:1920.0 ty:423.7`
- Expected finalTransform tx: After scaling preferredTransform's tx (1920), it becomes 1920*0.5625 = 1080
- Then add centring: 1080 + (0/0.5625) = 1080 + 0 = **1080** (but we see 1920 - WRONG!)
- Expected finalTransform ty: After scaling preferredTransform's ty (1080), it becomes 1080*0.5625 = 607.5
- Then add centring: 607.5 + (656.25/0.5625) = 607.5 + 1166.67 = **1774.17** (but we see 423.7 - WRONG!)

**Conclusion:** The current calculation is producing completely wrong values. The division by scale is definitely incorrect.

---

## Checklist Before Each Attempt

- [ ] Check this list - has this approach been tried?
- [ ] Review diagnostic logs for affected clips
- [ ] Understand current transform calculation flow
- [ ] Test on all clip types (90°, 180°, identity, unusual aspect)
- [ ] Verify working clips still work
- [ ] Document attempt in this file
- [ ] Commit with clear message
- [ ] If fails, revert immediately and document why

---

**Last Updated:** [Current Date]  
**Current Status:** ✅ RESOLVED - Option A (Match TapeExporter) fixed all misalignment issues. All clips render correctly.

**Resolution:** Use `concatenating()` for transform composition instead of `scaledBy()` + `translatedBy()`, and do NOT divide translation by scale. This matches the working TapeExporter approach.

