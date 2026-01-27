## Summary
Improves responsiveness by moving tape persistence off the main thread and removing blocking waits during playback teardown and image-to-video preparation.

## Purpose & scope
Reduce UI stalls during asset loading, playback transitions, and tape title edits by debouncing disk writes, loading saved tapes asynchronously, and avoiding blocking waits in media processing.

## Key UI components used
- `TapePlayerView`
- `TapeCardView`

## Data flow (ViewModel → Model → Persistence)
- `TapesStore` captures a snapshot of `Tape` models on the main actor.
- A background persistence actor encodes/decodes JSON and writes to `tapes.json`.
- Playback preparation uses async waits rather than blocking semaphores during image-based clip encoding.

## Testing or QA considerations
- Import 30–100 clips and verify the UI remains responsive while loading.
- Open and dismiss playback repeatedly; confirm dismissal does not hang.
- Rename tapes rapidly and confirm keyboard presentation feels immediate.
- Verify `tapes.json` still loads correctly after app relaunch.

## Related tickets or links
- None
