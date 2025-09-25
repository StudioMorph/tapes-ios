# TAPES (REELZ) — MVP Runbook v2

This Runbook defines the **design system, components, flows, technical rules, and platform-specific stubs**
for the MVP of the TAPES app (codename REELZ). It is structured to be digestible by developers and AI assistants (Cursor).

---

## 1. Design Tokens (Light/Dark)

- **Colours**
  - Primary Red: #E50914
  - Secondary Gray: #222
  - Background Light: #FFFFFF
  - Background Dark: #000000
  - Text Primary: #FFFFFF (dark bg), #000000 (light bg)
- **Typography**
  - Heading: SF Pro Display / Roboto, Bold, 20pt
  - Body: SF Pro Text / Roboto, Regular, 16pt
- **Spacing**
  - XS = 4pt, S = 8pt, M = 16pt, L = 24pt, XL = 32pt
- **Shape**
  - Buttons: Rounded 12pt
  - Thumbnails: Rounded 8pt
- **Mode**
  - Support both **Light** and **Dark**

---

## 2. Components

- **FAB (Record/Swipe-to-Snap)**
  - States: Camera, Add from Gallery, Transition
  - Gesture: swipe horizontally to change function
- **Thumbnail Carousel**
  - Center record button fixed; carousel snaps so one item is on each side
  - Thumbnails: 16:9 ratio, width = (screenWidth - 64) / 2
- **Clip Edit Sheet**
  - Options: Trim, Rotate 90°, Fit/Fill, Share (stub), Delete
- **Global Tape Settings**
  - Orientation: Portrait (9:16) or Landscape (16:9)
  - Conflicting Aspect Ratios: Fill / Fit
  - Transition Style: None / Crossfade / Slide L→R / Slide R→L / Randomise
  - Transition Duration: slider, clamp Randomise to 0.5s
- **Player Controls**
  - Play, Pause, Restart, Clip Index
- **Casting**
  - iOS: AVRoutePickerView wrapper (AirPlayButton)
  - Android: CastButton stub (Toast)

---

## 3. Screen Layouts

### Timeline Screen
- Carousel with thumbnails and center FAB
- Placeholders ("+") at start and end when clips exist
- Swipe-to-Snap behaviour for FAB

### Clip Edit Tray
- Opens on tap of thumbnail
- Actions: Trim → native editor, Rotate, Fit/Fill, Delete

### Tape Settings Sheet
- Global controls for orientation, transitions, aspect, duration

### Player Screen
- Plays preview with transitions
- Play Options button → Preview or Merge & Save

---

## 4. User Flows

- **Create Tape**
  - Launch → New Tape with start/end "+"
  - FAB: record or add clip
- **Insert Clip**
  - Carousel snaps → insert at center slot
- **Edit Clip**
  - Tap thumbnail → Edit tray
  - Trim, Rotate, Fit/Fill, Delete
- **Preview Playback**
  - WYSIWYG transitions, seeded Randomise deterministic
- **Export**
  - iOS: AVFoundation with video+audio fades, 1080p
  - Android: FFmpegKit with xfade+acrossfade, 1080p scaled/padded
- **Casting**
  - iOS: AirPlayButton visible if devices available
  - Android: CastButton shows Toast

---

## 5. Technical Rules

### Transitions
- Supported: None, Crossfade, Slide L→R, Slide R→L, Randomise
- Randomise seeded by Tape UUID → consistent preview/export
- Clamp duration: Randomise max 0.5s

### Export
- iOS: AVAssetExportSession, alternating A/B tracks with AVAudioMix ramps
- Android: FFmpegKit filtergraph with xfade + acrossfade, normalized to 1080p
- Output: Movies/Tapes (Android), Photos/Tapes Album (iOS)

### Casting
- iOS: AVRouteDetector + AVRoutePickerView
- Android: CastManager (poll 10s), CastButton Toast

### QA
- See `QA_SmokeTest_Checklist.md`

---

## 6. Dependencies

- iOS:
  - AVFoundation, Photos
- Android:
  - FFmpegKit (`com.arthenica:ffmpeg-kit-full:6.0-2`)
  - Media3 Transformer (fallback concat)
  - Jetpack Compose

---

## 7. Deliverables

This Runbook is bundled with:
- **iOS stubs** (exporter, cast manager, AirPlay)
- **Android stubs** (FFmpeg exporter, cast manager/button)
- **QA checklist**
- **Docs** for casting, export, iOS/Android notes

Cursor should follow: Tokens → Components → Layouts → Flows → Export → QA.

---

# End of Runbook v2
