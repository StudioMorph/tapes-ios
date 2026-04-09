# Clip Trimming

## Summary

Non-destructive video clip trimming and per-clip volume control via a full-screen overlay with an Apple Photos-style frame timeline and vertical volume sliders.

## Purpose & Scope

Allows users to trim the beginning and end of video clips within a tape without modifying the original asset, and to adjust per-clip video volume (and background music volume when available). Trim points and volume levels are stored on the Clip model and respected during playback and composition building/export.

## Key UI Components

- **ClipTrimView** (`Tapes/Views/ClipTrimView.swift`) — Full-screen modal containing:
  - **Video preview** — Full-screen, edge-to-edge AVPlayer layer as the background, ignoring safe areas. Uses orientation-aware video gravity: fills when video orientation matches device orientation, fits (letterbox) when they differ — matching the main tape playback view.
  - **Top bar** — Cancel and Done buttons with "Trim Clip" title, over a gradient fade.
  - **Volume sliders** — Vertical capsule-style sliders positioned on the right side, above the trimmer:
    - **Video volume** — Always visible. Speaker icon changes dynamically based on level (muted, low, medium, high).
    - **Background music volume** — Only visible when the tape has background music configured. Uses a music note icon.
    - Sliders use `.ultraThinMaterial` for the track background with a white-fill indicator, matching iOS Control Centre aesthetics.
  - **Frame timeline strip** — Horizontal row of extracted video frame thumbnails (15 frames via `AVAssetImageGenerator`).
  - **Yellow trim handles** — Draggable left and right chevron handles to set `trimStart` and `trimEnd`.
  - **Playhead** — White vertical indicator showing current playback position.
  - **Playback controls** — Play/pause button; playback auto-stops at the trim end boundary and loops back to trim start.
  - **Done** (saves trim + volumes) and **Cancel** (discards changes) toolbar buttons.
- **VerticalVolumeSlider** (`Tapes/DesignSystem/VerticalVolumeSlider.swift`) — Reusable vertical slider component with material blur background, drag gesture-based input, and dynamic icon updates.

## Data Model

### `Clip` additions
- `trimStart: TimeInterval` (default 0) — Seconds to trim from the beginning.
- `trimEnd: TimeInterval` (default 0) — Seconds to trim from the end.
- `trimmedDuration: TimeInterval` — Computed: `duration - trimStart - trimEnd`.
- `isTrimmed: Bool` — Computed: true when either trim value is > 0.
- `setTrim(start:end:)` — Mutating setter.
- `clearTrim()` — Resets both to 0.
- `volume: Double?` — Per-clip video audio volume (0.0–1.0). `nil` means full volume (1.0).
- `musicVolume: Double?` — Per-clip background music volume (0.0–1.0). `nil` means full volume (1.0).

All fields are backward compatible via `decodeIfPresent` with sensible defaults.

## Data Flow

### Edit Clip View
1. User taps a video clip thumbnail in the carousel.
2. `TapeCardView` presents `ClipTrimView` as a full-screen cover, passing the full `Tape` object.
3. `ClipTrimView` loads the AVAsset (from local URL or Photos library), extracts frame thumbnails, and determines video natural size for orientation-aware gravity.
4. User drags trim handles to set start/end points; preview plays within the trimmed range.
5. User adjusts volume sliders; the preview player's volume and background music player's volume update in real-time.
6. On Done, `trimStart`, `trimEnd`, `volume`, and `musicVolume` are written to the Clip model and persisted via `TapesStore.updateTape`. Volume values are stored as `nil` when matching the tape default to keep persistence lean.

### Playback View
1. Volume sliders appear in the controls overlay alongside the progress bar and playback controls, on the right side above the progress bar.
2. Sliders show/hide with the controls overlay (tap to toggle).
3. When clips transition (next/previous/swipe/auto-advance), the slider values update to reflect the current clip's `volume` and `musicVolume`.
4. Dragging a slider updates audio in real-time and auto-persists the change to the clip model.
5. On dismiss, the updated tape (with any volume changes) is saved back to `TapesStore`.

### Composition & Export
1. `TapeCompositionBuilder` uses `clip.volume` to set `AVMutableAudioMixInputParameters` volume levels for each clip's audio track.
2. `TapeExporter.addBackgroundMusic` applies `clip.musicVolume` (absolute value, defaulting to `tape.musicVolume`) at each segment's start time.
3. Both values are absolute (0.0–1.0), not multipliers on top of the tape-level setting.

## Scope Limitations

- **Video clips only** — Image clips are not tappable for trimming.
- **Non-destructive** — Original asset is never modified; only trim and volume metadata is stored.

## Testing / QA Considerations

- Verify trim points persist after app restart.
- Verify playback uses trimmed range (audio and video both start at `trimStart`).
- Verify trim handles cannot overlap or exceed clip bounds.
- Verify Cancel in Edit Clip discards unsaved trim and volume changes.
- Verify volume slider adjustments update preview playback volume in real-time (both Edit Clip and Playback views).
- Verify per-clip volume levels are applied during full tape playback and export.
- Verify background music slider only appears when the tape has background music configured.
- Verify the video preview fills when matching device orientation and fits when not.
- Verify slider values update correctly when transitioning between clips during playback.
- Verify volume changes made during playback persist after dismissing the player.
- Verify backward compatibility with clips saved before volume properties were added.
