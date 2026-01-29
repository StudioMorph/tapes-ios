## Summary
Switches preview playback from a single merged composition to per-clip playback with runtime transitions and a small prefetch window.

## Purpose & scope
Make preview playback start fast, skip instantly, and avoid memory growth by playing clips as individual items with lightweight transitions, similar to Apple Memories.

## Key UI components used
- `TapePlayerView`
- `PlayerControls`
- `PlayerProgressBar`
- `PlayerSkipToast`

## Data flow (ViewModel → Model → Persistence)
- `TapePlayerView` asks `TapeCompositionBuilder` for a lightweight timeline.
- Each clip is resolved on demand into a single-clip `AVPlayerItem`.
- A small in-memory cache holds the current clip plus the next two.

## Testing or QA considerations
- Start playback on a tape with 50+ clips and confirm the first clip plays quickly.
- Skip rapidly (next/previous) and confirm instant response without snapback.
- Scrub across the timeline and ensure the correct clip loads and plays.
- Validate transitions: none, crossfade, slide L→R, slide R→L, randomise.
- Confirm memory usage remains stable while long tapes play.

## Related tickets or links
- None
