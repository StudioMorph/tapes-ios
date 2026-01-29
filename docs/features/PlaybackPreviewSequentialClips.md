## Summary
Switches preview playback from a single merged composition to per-clip playback with runtime transitions and sequential preloading.

## Purpose & scope
Make preview playback start fast, skip instantly, and avoid timeline rebuilds by playing clips as individual items with lightweight transitions, similar to Apple Memories.

## Key UI components used
- `TapePlayerView`
- `PlayerControls`
- `PlayerProgressBar`
- `PlayerSkipToast`

## Data flow (ViewModel → Model → Persistence)
- `TapePlayerView` asks `TapeCompositionBuilder` for a lightweight timeline.
- Each clip is resolved on demand into a single-clip `AVPlayerItem`.
- A background loader preloads clips sequentially after the current clip finishes loading and keeps them cached.
- Scrubbing seeks only within the active clip; clip changes remain button/gesture driven.

## Testing or QA considerations
- Start playback on a tape with 50+ clips and confirm the first clip plays quickly.
- Skip rapidly (next/previous) and confirm instant response without snapback.
- Scrub within a clip and confirm the clip does not change.
- Validate transitions: none, crossfade, slide L→R, slide R→L, randomise.
- Confirm sequential preloading progresses through the remaining clips without reloading earlier ones.

## Related tickets or links
- None
