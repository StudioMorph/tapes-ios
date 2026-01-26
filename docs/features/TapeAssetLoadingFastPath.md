## Summary
Tape creation now relies on lightweight clip metadata and thumbnails so timelines build quickly, with full asset rendering deferred to preview playback.

## Purpose & scope
This update ensures the timeline only needs clip identifiers, basic metadata (duration, type), and thumbnails during tape creation. AVAsset composition and full rendering are reserved for the playback/preview path. Photos-backed videos avoid file copy during import.

## Key UI components used
- `TapeCardView`
- `ThumbnailView`
- `ClipThumbnailView`

## Data flow (ViewModel → Model → Persistence)
- `TapesStore` builds `Clip` models from `PickedMedia` with minimal metadata and persists them.
- `TapesStore` resolves missing durations and thumbnails asynchronously, preferring Photos metadata for assets with identifiers, and requests higher-resolution thumbnails for clearer UI.
- `Tape` and `Clip` persist via JSON in the existing storage layer.

## Testing or QA considerations
- Confirm adding a large batch of clips keeps the timeline responsive.
- Verify thumbnails and durations populate after import for Photos-backed and local URL videos.
- Check limited Photos permission still yields thumbnails where available.
- Ensure playback still resolves full assets only in the preview flow.

## Related tickets or links
- None.
