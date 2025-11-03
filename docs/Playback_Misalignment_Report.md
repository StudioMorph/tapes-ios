# Video Mispositioning Investigation Report

**Date:** [Date]  
**Investigator:** [Name]  
**Status:** Diagnostic Phase - No Fixes Applied

---

## Executive Summary

**Status:** ✅ **RESOLVED**

Video misalignment affected clips with 180° rotations and unusual aspect ratios. Images were always unaffected. Root cause was incorrect transform composition method (`scaledBy()` + `translatedBy()` with division by scale) instead of using `concatenating()` matching the working TapeExporter approach. Fixed in commit `1d034f9` (Option A - Match TapeExporter).

---

## Scope

- **Playback view/path only** (videos during playback)
- **Asset types tested:**
  - Recent HEVC videos
  - Older H.264 videos
  - Photos-edited videos (cropped/rotated)
  - Screen recordings
  - iCloud-only assets
  - Local file assets
- **Images:** Confirmed always render correctly (baseline)

---

## Evidence Log

### Test Case 1: [Description - e.g., "HEVC Video with Non-Identity Transform"]

**Clip Details:**
- Asset ID: `[hashed]`
- File: `[basename]`
- Type: Video
- Codec: HEVC
- Edited: Yes/No

**Log Entry:**
```
[PLAYBACK] clip=X clipID=... assetID=... fileURL=... type=video naturalSize=...x... preferredTransform=[...] displaySize=...x... cleanAperture=... pixelAspectRatio=... renderSize=...x... instructionCount=X finalTransform=[...] videoGravity=... layerBounds=... containerSize=... safeArea=(...) scaleMode=... ttfFrame=... layoutStable=... isCloud=false isEdited=false
```

**Screenshot:** [Screenshot reference or path]

**Misalignment Description:**
- Off-centre: [Yes/No, describe if yes]
- Wrong size: [Yes/No, describe if yes]
- Position offset: [X pixels left/right, Y pixels up/down]

**Root Cause Hypothesis:**
[Based on log data - e.g., "Clean aperture + non-identity preferredTransform suggests transform calculation doesn't account for aperture"]

**File:Line References:**
- Transform calculation: `TapeCompositionBuilder.swift:1046-1046` (baseTransform)
- Render size: `TapeCompositionBuilder.swift:701-708` (renderSize)
- Composition instruction: `TapeCompositionBuilder.swift:912-924` (baseLayerInstruction)
- VideoPlayer usage: `TapePlayerView.swift:29` (no videoGravity control)

---

### Test Case 2: [Description]

[Repeat structure]

---

### Test Case 3: [Description]

[Repeat structure]

---

## Code Audit Findings

### 1. VideoGravity Configuration

**Location:** `TapePlayerView.swift:29`
- **Finding:** SwiftUI `VideoPlayer` used without explicit `videoGravity` control
- **Impact:** Default AVKit behaviour (likely `.resizeAspectFill` or `.resizeAspect`) may conflict with composition transforms
- **Reference:** No direct access to `AVPlayerLayer.videoGravity` from SwiftUI `VideoPlayer`

### 2. Transform Application

**Location:** `TapeCompositionBuilder.swift:1016-1046`
- **Function:** `baseTransform(for:renderSize:scaleMode:)`
- **Logic:**
  1. Applies `preferredTransform` to `naturalSize` to get display dimensions
  2. Computes scale (min for fit, max for fill)
  3. Scales `preferredTransform` by scale factor
  4. Translates to centre within renderSize
- **Potential Issues:**
  - Clean aperture not considered
  - Pixel aspect ratio not explicitly applied
  - Transform concatenation order (scale before translation may cause offset)

### 3. Render Size

**Location:** `TapeCompositionBuilder.swift:701-708`
- **Values:**
  - Portrait: 1080x1920
  - Landscape: 1920x1080
- **Finding:** Fixed render size - may not match device display or container
- **Composition:** `AVMutableVideoComposition.renderSize` set to this fixed value (line 377)

### 4. PreferredTransform Handling

**Location:** `TapeCompositionBuilder.swift:409`
- **Loaded:** `videoTrack.load(.preferredTransform)`
- **Usage:** Applied in `baseTransform` (line 1019)
- **Finding:** Transform applied directly without validating or normalising

### 5. Container/Layout

**Location:** `TapePlayerView.swift:24-36`
- **Finding:** `VideoPlayer` embedded in `ZStack` with black background
- **No explicit sizing constraints** - relies on SwiftUI default behaviour
- **Safe area:** Not explicitly handled in player container
- **Layout changes:** No tracking of geometry changes that might affect positioning

### 6. Composition Instructions

**Location:** `TapeCompositionBuilder.swift:912-924`
- **Function:** `baseLayerInstruction(for:track:renderSize:scaleMode:at:)`
- **Transform set:** Line 920 - `instruction.setTransform(transform, at: time)`
- **Finding:** Transform computed once at instruction creation time, not validated against actual layer bounds

### 7. Aspect Ratio Logic

**Location:** Not found
- **Finding:** No explicit `.aspectRatio()` or `.scaledToFill()`/`.scaledToFit()` modifiers in `TapePlayerView`
- **Impact:** VideoPlayer uses default AVKit scaling, which may conflict with composition transforms

### 8. Clean Aperture & Pixel Aspect Ratio

**Location:** `TapeCompositionBuilder.swift:415-437`
- **Status:** Now captured in diagnostics (new code)
- **Finding:** Previously not considered in transform calculations
- **Impact:** Videos with non-standard clean aperture may render incorrectly

### 9. Transition Containers

**Location:** `TapeCompositionBuilder.swift:926-1044`
- **Functions:** `configureTransition`, `applySlideTransition`
- **Finding:** Transitions apply additional transforms that may persist or conflict

---

## Root Cause Hypotheses

### Hypothesis 1: Clean Aperture + PreferredTransform Mismatch

**Evidence:**
- [Log entries showing cleanAperture != naturalSize with non-identity preferredTransform]

**Mechanism:**
- `baseTransform` computes display size using `naturalSize.applying(preferredTransform)`
- Clean aperture defines actual displayable region (may be smaller)
- Transform assumes full naturalSize is displayable, causing offset

**Proof Required:**
- Compare `cleanAperture` vs `naturalSize` for failing clips
- Verify transform calculation doesn't account for aperture

**File References:**
- `TapeCompositionBuilder.swift:1021` - `naturalSize.applying(preferredTransform)`
- `TapeCompositionBuilder.swift:418` - Clean aperture extraction (diagnostic only)

---

### Hypothesis 2: Pixel Aspect Ratio Not 1:1

**Evidence:**
- [Log entries showing pixelAspectRatio != 1:1]

**Mechanism:**
- Non-square pixels require additional scaling
- Current transform assumes square pixels
- Display size calculation incorrect

**Proof Required:**
- Verify `pixelAspectRatio` for failing clips
- Check if transform accounts for PAR

---

### Hypothesis 3: VideoGravity Conflict

**Evidence:**
- [Observations: some clips render correctly, others don't, pattern suggests VideoPlayer default behaviour]

**Mechanism:**
- `VideoPlayer` applies default AVKit scaling (likely `.resizeAspectFill`)
- Composition transform also applies scaling
- Double-scaling or conflicting transforms cause misalignment

**Proof Required:**
- Cannot verify without accessing `AVPlayerLayer` (requires `UIViewRepresentable` wrapper)
- Compare clips with different transform characteristics

**File References:**
- `TapePlayerView.swift:29` - `VideoPlayer(player: player)` (no gravity control)

---

### Hypothesis 4: Layout Size Changes After First Frame

**Evidence:**
- [Timing logs showing layoutStabilisedTime > timeToFirstFrame]

**Mechanism:**
- First frame renders before container size stabilises
- Composition transform computed with initial (wrong) size
- Layout settles, but transform already applied

**Proof Required:**
- Compare `timeToFirstFrame` vs `layoutStabilisedTime`
- Check if container size changes during initial render

**File References:**
- `TapePlayerView.swift` - No geometry tracking (would need `GeometryReader`)

---

### Hypothesis 5: Render Size Mismatch

**Evidence:**
- [Log entries showing renderSize != containerSize]

**Mechanism:**
- Composition renderSize fixed (1080x1920 or 1920x1080)
- Device/container may have different aspect ratio
- Transform assumes composition size, but display scales differently

**Proof Required:**
- Compare `renderSize` vs `containerSize` in logs
- Check device display dimensions

**File References:**
- `TapeCompositionBuilder.swift:377` - `videoComposition.renderSize = timeline.renderSize`
- `TapeCompositionBuilder.swift:701-708` - Fixed render size values

---

### Hypothesis 6: Fit/Fill Applied Pre-Transform

**Evidence:**
- [Clips with overrideScaleMode behave differently than tape default]

**Mechanism:**
- Scale mode applied to `naturalSize` before `preferredTransform` considered
- Transform then applied on incorrectly scaled dimensions
- Final size/position incorrect

**Proof Required:**
- Compare clips with `.fit` vs `.fill` vs default
- Verify scale calculation order

**File References:**
- `TapeCompositionBuilder.swift:1032-1038` - Scale mode selection
- `TapeCompositionBuilder.swift:1040` - Transform scaling

---

### Hypothesis 7: Transition Container Residual Transform

**Evidence:**
- [Misalignment occurs after transitions or at clip boundaries]

**Mechanism:**
- Transition animations apply transforms to layers
- Transform not reset after transition completes
- Next clip inherits incorrect transform

**Proof Required:**
- Check if misalignment correlates with transition presence
- Verify transform reset after transition

**File References:**
- `TapeCompositionBuilder.swift:947-957` - Transition transform ramps
- `TapeCompositionBuilder.swift:1040-1044` - Transform concatenation

---

## Minimal Next Steps (Deferred - No Code Yet)

### 1. Compute Display Rect Post-Transform

**Action:** Calculate display rect using clean aperture + preferredTransform + PAR, then apply scaling

**Risk:** Medium - May affect currently correct clips  
**Effort:** M (2-4 hours)

**File:** `TapeCompositionBuilder.swift:1046-1046`

---

### 2. Stabilise Layout Before Play

**Action:** Wait for container geometry to stabilise before starting playback or computing transforms

**Risk:** Low - May introduce slight delay  
**Effort:** S (1-2 hours)

**File:** `TapePlayerView.swift:65-70` (onAppear)

---

### 3. Unify VideoGravity

**Action:** Wrap `VideoPlayer` in `UIViewRepresentable` to access `AVPlayerLayer` and set explicit `videoGravity` (e.g., `.resizeAspect` to match composition)

**Risk:** High - May break existing correct behaviour  
**Effort:** M (3-5 hours)

**File:** New file + `TapePlayerView.swift:29`

---

### 4. Read Clean Aperture in Transform Calculation

**Action:** Use clean aperture dimensions (if available) instead of naturalSize when computing display rect

**Risk:** Medium - May cause edge cases if aperture missing  
**Effort:** S (1-2 hours)

**File:** `TapeCompositionBuilder.swift:1021`

---

### 5. Apply Pixel Aspect Ratio Scaling

**Action:** Multiply scale factors by PAR when computing final transform

**Risk:** Low - Only affects non-square pixel videos  
**Effort:** S (1 hour)

**File:** `TapeCompositionBuilder.swift:1040`

---

### 6. Validate Transform Against Composition RenderSize

**Action:** Ensure computed transform produces output that fits exactly within renderSize (accounting for all factors)

**Risk:** Low - Validation only  
**Effort:** S (1 hour)

**File:** `TapeCompositionBuilder.swift:1046-1046`

---

### 7. Reset Transition Transforms

**Action:** Explicitly reset layer transforms after transition completes to prevent carryover

**Risk:** Medium - May affect transition smoothness  
**Effort:** M (2-3 hours)

**File:** `TapeCompositionBuilder.swift:947-957`

---

## Testing Methodology

### Systematic Test Cases

1. **Recent HEVC (iPhone camera)**
   - Expected: No misalignment
   - Test: 5 clips

2. **Older H.264**
   - Expected: May misalign if transform handling incorrect
   - Test: 5 clips

3. **Photos-edited (cropped)**
   - Expected: May misalign if clean aperture not handled
   - Test: 5 clips

4. **Photos-edited (rotated)**
   - Expected: May misalign if preferredTransform incorrect
   - Test: 5 clips

5. **Screen recordings**
   - Expected: Usually no transform, should be fine
   - Test: 3 clips

6. **iCloud-only assets**
   - Expected: May misalign if placeholder handling incorrect
   - Test: 3 clips

7. **Mixed scale modes**
   - Expected: May misalign if fit/fill logic incorrect
   - Test: 5 clips (mix of fit, fill, default)

### Logging Strategy

- Enable `PlaybackDiagnostics.isEnabled = true` (DEBUG builds only)
- Play each test tape fully
- Capture logs for all clip transitions
- Take screenshots of any misaligned clips
- Document exact misalignment (pixels offset, direction)

---

## Conclusion

**Root Cause Identified:** Incorrect transform composition method in `baseTransform()`. The code used `scaledBy()` + `translatedBy()` with division by scale, which applied translations in the wrong coordinate space (scaled space instead of render space).

**Solution Applied:** Changed to use `concatenating()` for both scale and translation transforms, matching the working `TapeExporter.swift` approach exactly. Removed division by scale on translation.

**Result:** All clips (including 180° rotations and unusual aspect ratios) now render correctly centred. No regression on previously working clips.

**Key Takeaway:** Always reference existing working code (`TapeExporter`) for proven patterns rather than inventing new approaches.

**Fixed in Commit:** `1d034f9` (Option A from `Playback_Misalignment_Attempts.md`)

---

## Appendix: Diagnostic Code Locations

- `Tapes/Playback/PlaybackDiagnostics.swift` - Diagnostic framework
- `Tapes/Playback/TapeCompositionBuilder.swift:415-437` - Clean aperture/PAR capture
- `Tapes/Playback/TapeCompositionBuilder.swift:442-458` - Context metadata assignment
- `Tapes/Playback/PlaybackEngine.swift:553-555` - Clip change detection
- `Tapes/Playback/PlaybackEngine.swift:567-642` - Diagnostic logging

---

**Note:** This is a diagnostic report. No fixes have been implemented. All recommendations are deferred pending root cause confirmation.

