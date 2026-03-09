# Clip Trimming

## Summary

Non-destructive video clip trimming via an Apple Photos-style frame timeline with draggable start/end handles.

## Purpose & Scope

Allows users to trim the beginning and end of video clips within a tape without modifying the original asset. Trim points are stored on the Clip model and respected during playback and composition building.

## Key UI Components

- **Scissors icon** — Centered on video clip thumbnails in the carousel to indicate the clip is tappable for editing. Only shown for video clips.
- **ClipTrimView** (`Tapes/Views/ClipTrimView.swift`) — Full-screen modal containing:
  - **Video preview** — AVPlayer-based playback of the clip at the top.
  - **Frame timeline strip** — Horizontal row of extracted video frame thumbnails (15 frames via `AVAssetImageGenerator`).
  - **Yellow trim handles** — Draggable left and right chevron handles to set `trimStart` and `trimEnd`.
  - **Playhead** — White vertical indicator showing current playback position.
  - **Time labels** — Current position and trimmed duration.
  - **Playback controls** — Play/pause button; playback auto-stops at the trim end boundary and loops back to trim start.
  - **Done** (saves trim) and **Cancel** (discards changes) toolbar buttons.

## Data Model

### `Clip` additions
- `trimStart: TimeInterval` (default 0) — Seconds to trim from the beginning.
- `trimEnd: TimeInterval` (default 0) — Seconds to trim from the end.
- `trimmedDuration: TimeInterval` — Computed: `duration - trimStart - trimEnd`.
- `isTrimmed: Bool` — Computed: true when either trim value is > 0.
- `setTrim(start:end:)` — Mutating setter.
- `clearTrim()` — Resets both to 0.

Backward compatible via `decodeIfPresent` with default values of 0.

## Data Flow

1. User taps a video clip thumbnail in the carousel (scissors icon is visible).
2. `TapeCardView` presents `ClipTrimView` as a full-screen cover.
3. `ClipTrimView` loads the AVAsset (from local URL or Photos library) and extracts frame thumbnails.
4. User drags trim handles to set start/end points; preview plays within the trimmed range.
5. On Done, `trimStart` and `trimEnd` are written to the Clip model and persisted via `TapesStore.updateTape`.
6. During playback, `TapeCompositionBuilder.loadMetadata` uses `trimmedDuration` for timeline duration.
7. During composition building, `insertTimeRange` uses `trimStart` as the source start offset and `trimmedDuration` as the source duration.

## Scope Limitations

- **Video clips only** — Image clips do not show the scissors icon and are not tappable for trimming.
- **Non-destructive** — Original asset is never modified; only trim metadata is stored.
- The duration badge on thumbnails shows `trimmedDuration` when a clip is trimmed.

## Testing / QA Considerations

- Verify trim points persist after app restart.
- Verify playback uses trimmed range (audio and video both start at `trimStart`).
- Verify trim handles cannot overlap or exceed clip bounds.
- Verify Cancel discards unsaved trim changes.
- Verify the scissors icon only appears on video clips, not images or placeholders.
- Verify backward compatibility with clips saved before this feature (trimStart/trimEnd default to 0).
