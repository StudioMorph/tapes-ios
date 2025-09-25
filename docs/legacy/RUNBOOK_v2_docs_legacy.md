# TAPES — Runbook v2 (MVP)

This document is the **single source of truth** for building the TAPES MVP.  
Structure: **Design Tokens → Components → Screen Layouts → User Flows → Technical Rules → Build → QA**.

---

## Design Tokens (Light/Dark)
> Implement as platform-native constants (Swift enums / Kotlin objects).

### Colour
- **Primary/Accent:** Red 600 / Red 500 (dark), Red 700 / Red 600 (light)
- **Surface:** `#0B0B0F` dark / `#FFFFFF` light
- **On-Surface (Text):** `#FFFFFF` dark / `#0B0B0F` light
- **Muted:** grayscale ramp (8–96)

### Typography
- Headline: 24/28, Semibold  
- Title: 18/24, Semibold  
- Body: 16/22, Regular  
- Caption: 12/16, Regular

### Spacing & Radii
- Spacing scale: 4, 8, 12, 16, 20, 24  
- Radius: 12 (cards), 20 (sheets), full (FAB)

---

## Components
- **FAB (Record/Gallery/Transition)**
  - Red circular button, center anchored in tape carousel.
  - Swipe left/right on FAB cycles mode: Camera → Gallery → Transition.
- **Thumbnail**
  - 16:9; width = `(screenWidth - 64)/2`; consistent min tap target.
  - Shows clip index label (`TapeName/pos:N`).
- **Carousel**
  - **FAB fixed** at center; thumbnails move; **snap** so one item sits on each side of FAB.
- **Edit Sheet**
  - **Trim** (native), **Rotate 90°**, **Fit/Fill**, **Share/AirDrop**, **Remove** (confirm).
- **Settings Sheet (Tape-Level)**
  - Orientation: **Portrait 9:16** / **Landscape 16:9**
  - Conflicting Aspect Ratios: **Fit** / **Fill**
  - Transition: **None / Crossfade / Slide L→R / Slide R→L / Randomise**
  - Transition Duration: **0.2–1.0s**; **Randomise clamps to 0.5s max**.
- **Player Controls**
  - Restart, Play/Pause, Clip indicator, **Play Action Sheet** (Preview | Merge & Save)
- **Cast Button**
  - iOS: **AVRoutePickerView** (shows only when devices available)
  - Android: Cast button (hidden when no devices; toast placeholder)

---

## Screen Layouts
- **Tape Builder (single screen MVP)**
  - Top bar: Title, Settings (gear), (iOS) AirPlay button if available
  - Main: Player canvas (orientation-derived aspect), overlay controls
  - Bottom: Snap carousel with fixed-center FAB
  - Edit Sheet (modal), Settings Sheet (modal)

---

## User Flows
1. **Create Tape** → empty timeline with start/end “+”, FAB centered.
2. **Insert Clip**
   - Swipe to position → **Record** or **Add from device** → clip inserts **at center**.
3. **Edit Clip**
   - Tap thumbnail → Edit Sheet → Trim/Rotate/Fit-Fill/Share/Remove.
4. **Set Transitions**
   - Global in Settings; **Randomise** uses **seeded sequence** (Tape UUID) & **0.5s clamp**.
5. **Preview**
   - ▶️ → **Preview Tape** → plays with transitions (WYSIWYG vs export).
6. **Export**
   - ▶️ → **Merge & Save** →
     - **iOS**: AVFoundation composition; **video slides/crossfade + audio fade**; 1080p output; Photos/Tapes.
     - **Android**: FFmpegKit; **xfade + acrossfade**; **1080p canvas**; Movies/Tapes.
7. **Cast**
   - Button shows only if devices exist. iOS: system picker; Android: toast (stub).

---

## Technical Rules
- **Storage model**: App is a **UI layer**; sources remain in Photos/MediaStore. No duplication beyond temporary export inputs.
- **Insertion math**: FAB is **fixed at center**; carousel snaps so **one item sits on each side**. New recordings insert **between** those two.
- **Aspect policy**: Tape orientation sets canvas. Per-clip Fit/Fill overrides global.  
- **Deterministic Random**: Seed RNG with Tape UUID; generate per-boundary sequence. No persistence required for MVP.
- **Clamp**: Randomise duration **≤ 0.5s**.
- **iOS Export**: 2 video + 2 audio tracks (A/B). Overlaps create transitions using opacity/transform ramps; audio via `AVMutableAudioMix` ramps.
- **Android Export**: FFmpegKit; pre-scale + pad every input to **1080p** (portrait/landscape), chain with `xfade` + `acrossfade`.

---

## Build & Dependencies
### iOS
- **AVFoundation**, **Photos**, **AVKit**
- Export preset: `AVAssetExportPreset1920x1080`
- Files:
  - `ios/TransitionPicker.swift`
  - `ios/TapeExporter.swift`
  - `ios/CastManager.swift`
  - `ios/AirPlayButton.swift`
  - `ios/TapePlayerView+CastOverlay.swift`

### Android
- **FFmpegKit**:
  ```gradle
  implementation "com.arthenica:ffmpeg-kit-full:6.0-2"
  ```
- **Media3 Transformer** (concat fallback)
- Files:
  - `android/TransitionPicker.kt`
  - `android/TapeExporter.kt`
  - `android/TapeExporter_FFmpeg.kt`
  - `android/TapeExporterMedia3Concat.kt`
  - `android/CastManager.kt`
  - `android/CastButton.kt`

---

## QA
Use `qa/QA_SmokeTest_Checklist.md` for step-by-step manual verification.  
Focus on: snapping correctness, transition parity preview/export, export destinations, and casting visibility.

---

## Future (Post-MVP)
- Text overlays, filters, per-clip transitions, cloud sync, share targets, custom toasts, full Cast integration.
