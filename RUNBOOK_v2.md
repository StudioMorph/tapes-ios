
# TAPES (REELZ) — MVP Runbook v2 (MASTER)

This document is the **single source of truth** for building the TAPES MVP.  
It merges the high-level summary (root runbook) with the deep technical detail (docs runbook).  
Structure: **Design Tokens → Components → Screen Layouts → User Flows → Technical Rules → Build → QA → Future**.

---

## 1. Design Tokens (Light/Dark)

- **Colours**
  - Primary Red: #E50914 (Root spec) / Red 600–700 variants (Docs spec)
  - Secondary Gray: #222
  - Surface: `#0B0B0F` dark / `#FFFFFF` light
  - On-Surface: `#FFFFFF` dark / `#0B0B0F` light
  - Muted: grayscale ramp (8–96)

- **Typography**
  - Heading / Headline: 20–24pt, Semibold/Bold (SF Pro / Roboto)
  - Title: 17/24, Semibold
  - Body: 16pt Regular
  - Caption: 12pt Regular

- **Spacing & Shape**
  - Spacing scale: 4, 8, 12, 16, 20, 24, 32
  - Radius: 12 (cards), 20 (sheets), full (FAB), 8 (thumbnails)

- **Mode**
  - Support both Light and Dark mode

---

## 2. Components

- **FAB (Record/Swipe-to-Snap)**
  - States: Camera, Add from Gallery, Transition
  - Swipe left/right to cycle modes
  - Red circular button, fixed center in carousel

- **Thumbnail Carousel**
  - Aspect: 16:9
  - Width: `(screenWidth - 64)/2`
  - Snap so one item sits left and one right of FAB
  - Shows index label (`TapeName/pos:N`)
  - Start/end placeholders: "+"
- **Media Import Positioning:**
  - **Red FAB (center)**: Insert clips at red line position using "between index" system
    - Red line corresponds to 0-based "between index" p ∈ [0…N] where N = clips.count
    - If red line is before first clip → p = 0 (insert at start)
    - If red line is between clip i and clip i+1 → p = i+1 (insert between them)
    - If red line is after last clip → p = N (insert at end)
    - Position is snapshotted when picker opens to handle user scrolling
  - **Left "+" placeholder**: Always insert at index 0 (start of timeline)
  - **Right "+" placeholder**: Always insert at index clips.count (end of timeline)
  - **Selection order**: Preserved for multi-select imports
  - **Array insertion**: Clips are inserted at the exact "between index" in the timeline array

- **Clip Edit Sheet**
  - Actions: Trim (native), Rotate 90°, Fit/Fill, Share/AirDrop, Remove (confirm)

- **Tape Settings Sheet (Global)**
  - Orientation: Portrait (9:16) or Landscape (16:9)
  - Conflicting Ratios: Fill / Fit
  - Transition: None / Crossfade / Slide L→R / Slide R→L / Randomise
  - Transition Duration: 0.2–1.0s (Randomise clamp ≤ 0.5s)

- **Player Controls**
  - Restart, Play/Pause, Clip index
  - Play button → full-screen player (preview only). Merge & Save only via tape card arrow.down.

- **Cast Button**
  - iOS: AVRoutePickerView (AirPlayButton) — visible only if devices available
  - Android: CastButton stub — toast if no devices

---

## 3. Screen Layouts

- **Timeline Screen (Tape Builder)**
  - Top: Title, Settings (gear), AirPlay button if available
  - Middle: Player canvas (orientation-driven), overlay controls
  - Bottom: Carousel with fixed FAB
  - Edit Sheet + Settings Sheet (modal)

- **Clip Edit Tray**
  - Tap thumbnail → Tray
  - Options: Trim, Rotate, Fit/Fill, Delete

- **Tape Settings**
  - Global orientation, transitions, aspect, duration

- **Player**
  - Preview playback with transitions (WYSIWYG)
  - Play opens player; Merge & Save via card arrow.down only

---

## 4. User Flows

1. **Create Tape**
   - Launch → new tape with "+" placeholders
   - FAB inserts clip

2. **Insert Clip**
   - Carousel snaps → insert at center
   - Options: Record or Add from device

3. **Edit Clip**
   - Tap → tray → Trim, Rotate, Fit/Fill, Delete

4. **Set Transitions**
   - Global setting; Randomise uses Tape UUID seed, clamped duration

5. **Preview**
   - ▶️ → Preview tape with transitions

6. **Export**
   - ▶️ → Merge & Save
   - iOS: AVFoundation composition, 2 video+audio tracks with crossfade+audio ramps
   - Android: FFmpegKit, 1080p scaled/padded, xfade+acrossfade

7. **Cast**
   - iOS: AirPlayButton shows if devices exist
   - Android: CastButton toast placeholder

---

## 5. Technical Rules

- **Storage Model**
  - App = UI layer only; clips remain in Photos/MediaStore
  - Temp export inputs only

- **Timeline Asset Loading**
  - Tape creation uses lightweight clip metadata and thumbnails only.
  - Full AVAsset composition/rendering is deferred to preview playback.

- **Persistence & Responsiveness**
  - Tape JSON persistence is debounced and runs off the main thread.
  - Playback teardown must avoid blocking the main thread.
  - Image-to-video preparation uses async completion rather than blocking waits.

- **Snapping / Insertion**
  - FAB fixed; carousel snaps around it
  - New clip inserts between left and right neighbor

- **Aspect Ratio**
  - Global orientation sets canvas
  - Per-clip Fit/Fill overrides global

- **Randomise Transitions**
  - Deterministic (Tape UUID as seed)
  - Clamp ≤ 0.5s

- **Export Implementation**
  - iOS: Reuses `TapeCompositionBuilder.buildExportComposition(for:)` (same pipeline as playback). Adds background music from cached Mubert track (looped, volume + fade-out). `TapeExporter.export(tape:)` → AVAssetExportSession → save to Photos. Single entry point: tape card arrow.down.
  - Android: FFmpegKit filtergraph (xfade + acrossfade)
- **Preview Composition (iOS)**
  - Preview playback uses per-clip `AVPlayerItem` instances via `TapePlayerViewModel` (MVVM).
  - Transitions are applied at runtime (crossfade/slide) using a two-player slot architecture.
  - Clips are preloaded sequentially with an LRU cache (10 entries, evicts on memory warning).
  - Global timeline scrubber seeks across the entire tape; scrubbing navigates between clips automatically.
  - Photo clips use a custom `AVVideoCompositing` pipeline (`StillImageVideoCompositor`) for real-time Ken Burns.
  - `AVAudioSession` configured as `.playback` with interruption and route-change handling.
  - Reduce Motion: slide transitions become crossfade; Ken Burns motion is disabled.
  - Export and non-preview flows still resolve `.image` clips by synthesising a short H.264 asset.
  - Photo assets are normalised for EXIF orientation; frames clamp to ≤1920×1080.
  - Builder split into 3 files: core (`TapeCompositionBuilder`), asset resolution (`+AssetResolution`), image encoding (`+ImageEncoding`).

---

## 6. Build & Dependencies

### iOS
- **Frameworks**: AVFoundation, Photos, AVKit
- **Export preset**: AVAssetExportPreset1920x1080
- **Files**:
  - Tapes/Views/Player/TapePlayerView.swift (thin View shell)
  - Tapes/Views/Player/TapePlayerViewModel.swift (playback state + logic)
  - Tapes/Components/AirPlayButton.swift (AVRoutePickerView wrapper)
  - Tapes/Components/Player*.swift (Header, Controls, ProgressBar, LoadingOverlay, SkipToast)
  - Tapes/Playback/TapeCompositionBuilder.swift (timeline + composition)
  - Tapes/Playback/TapeCompositionBuilder+AssetResolution.swift
  - Tapes/Playback/TapeCompositionBuilder+ImageEncoding.swift
  - Tapes/Playback/StillImageVideoCompositor.swift (real-time image rendering)
  - Tapes/Playback/AsyncSemaphore.swift (concurrency primitive)
  - Tapes/Export/TapeExporter.swift (export: builder + music + AVAssetExportSession)
  - Tapes/Export/ExportCoordinator.swift (UI state, permissions, album association)
  - Tapes/Export/iOSExporterBridge.swift (async bridge to TapeExporter)

### Android
- **Dependencies**:
  ```gradle
  implementation "com.arthenica:ffmpeg-kit-full:6.0-2"
  ```
- Media3 Transformer (concat fallback)
- **Files**:
  - android/TransitionPicker.kt
  - android/TapeExporter.kt
  - android/TapeExporter_FFmpeg.kt
  - android/TapeExporterMedia3Concat.kt
  - android/CastManager.kt
  - android/CastButton.kt

---

## 7. QA

- Use `qa/QA_SmokeTest_Checklist.md`
- Validate:
  - Snapping correctness
  - Transition parity (preview vs export)
  - Export destinations
  - Casting visibility

---

## 8. Future (Post-MVP)

- Per-clip transitions
- Filters & text overlays
- Cloud sync
- Share targets
- Full Cast integration

---

# End of MASTER Runbook v2
