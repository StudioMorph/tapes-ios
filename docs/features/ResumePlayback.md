# Resume Playback

## Summary

When a user opens a tape that has unwatched clips — either because they left mid-playback or because new clips arrived from a shared/collab contribution — a contextual menu on the play button offers to pick up where they left off or start from the beginning.

## Purpose & Scope

Eliminates the frustration of re-watching already-seen clips. Particularly valuable for collaborative tapes where new clips arrive regularly, and for long tapes where the user may not finish in one session.

## How It Works

### Tracking

- `Tape.watchedClipCount` (optional `Int`, persisted in `tapes.json`) records how many clips from the start have been watched. `nil` means never played.
- Updated in `TapePlayerViewModel` via `updateWatchedProgress(throughClip:)` — only increments forward (never decreases if the user skips backward).
- Tracked on: clip finishing naturally, user skipping forward (next button), swipe-forward gesture completing, and failed-clip skip.
- Follows the sparse encoding convention: omitted from JSON when `nil`.

### Resume Logic

- `Tape.resumeClipIndex` (computed) returns the first unwatched clip index, or `nil` if no resume is needed.
- Returns `nil` when: never played (`watchedClipCount` is `nil`), or all clips watched (`watchedClipCount >= clips.count`).
- Returns the index when: `0 < watchedClipCount < clips.count`.

### New Content Scenario

When new clips are appended (via `mergeClipsIntoSharedTape`), `clips.count` increases but `watchedClipCount` stays the same. This naturally creates a gap — `resumeClipIndex` points to the first new clip.

### User Prompt

When tapping the play button on a tape card, if `resumeClipIndex` is non-nil, a native iOS `Menu` pops up from the play icon with two options:
- **"Pick up where you left off"** — opens the player starting from the first unwatched clip.
- **"Start from the beginning"** — opens the player from clip 0.

If there's nothing to resume (`resumeClipIndex` is nil), a single tap plays from clip 0 immediately (no menu).

## Key Components

| File | Change |
|------|--------|
| `Models/Tape.swift` | `watchedClipCount` property, `resumeClipIndex` computed property, coding key + decoder |
| `Views/TapeCardView.swift` | Conditional `Menu` on play button when resume is available |
| `Components/TapesList.swift` | `onPlay` signature carries start clip index |
| `Views/TapesListView.swift` | `playbackStartClip` state, threaded to `TapePlayerView` |
| `Views/Share/SharedTapesView.swift` | Same pattern as TapesListView |
| `Views/Share/CollabTapesView.swift` | Same pattern as TapesListView |
| `Views/Player/TapePlayerView.swift` | Accepts `startAtClip` parameter, no dialog |
| `Views/Player/TapePlayerViewModel.swift` | `updateWatchedProgress` called on clip finish, next, swipe forward, and skip |

## Testing Considerations

1. Open a tape with 5+ clips. Leave after clip 2. Reopen — play button shows a menu offering clip 3.
2. Watch all clips. Reopen — single tap plays from start (no menu).
3. Watch all clips. Add new clips via collab/share. Reopen — menu offers the first new clip.
4. First time opening a tape — single tap plays from start (no menu).
5. Skip clips with the next button — they count as watched.
6. Swipe forward past a clip — counts as watched.
7. Swipe backward — does not reset watched count.
8. Ensure `watchedClipCount` persists across app relaunches (check `tapes.json`).
