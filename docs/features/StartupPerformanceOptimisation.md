## Summary
Eliminates startup stalls, the empty-state flash, and clunky interactions after launch by moving blob data out of JSON, throttling metadata tasks, batching UI updates, and deferring non-critical work.

## Purpose & scope
Address the root causes of slow startup and unresponsive UI that occur when the app loads tapes containing many clips with embedded thumbnail and image data.

## Changes

### 1. Loading state flag
- `TapesStore.isLoaded` prevents `EmptyStateView` from flashing while tapes load asynchronously from disk.

### 2. Blob externalisation (thumbnail & imageData)
- `TapePersistenceActor` now saves `thumbnail` and `imageData` as individual files under `Documents/clip_media/` (`{clipID}_thumb.jpg`, `{clipID}_image.dat`).
- JSON encoding strips blob fields, shrinking `tapes.json` from megabytes to kilobytes.
- On load, clips arrive with nil blobs; `Clip.thumbnailImage` and `Clip.resolvedImageData` lazy-load from disk on first access.
- Automatic migration: if the JSON still contains inline blobs (pre-migration), they are extracted to files and the JSON is re-saved without them.

### 3. Thumbnail caching
- `Clip.thumbnailImage` uses a static `NSCache<NSUUID, UIImage>` (80 items / 30 MB) so JPEG decoding happens once per clip per session.
- `Clip.hasThumbnail` checks both in-memory data and on-disk file existence, preventing unnecessary regeneration after migration.

### 4. Throttled metadata generation
- `generateThumbAndDuration` routes through a serial queue capped at 3 concurrent tasks (`maxConcurrentMetadata`), preventing CPU saturation on startup.

### 5. Batched clip mutations
- Thumbnail/duration updates are queued via `enqueueBatchUpdate` and flushed every 200 ms in a single `@Published` change, collapsing N re-renders into 1.

### 6. Deferred metadata restoration
- `restoreMissingClipMetadata` and `scheduleLegacyAlbumAssociation` are deferred 500 ms after load so the UI renders first.

### 7. Animation-free initial load
- `restoreEmptyTapeInvariant` and `insertEmptyTapeAtTop` accept an `animated` parameter; during initial load they insert silently without spring animations or reveal delays, and skip the redundant `autoSave`.

### 8. Reduced thumbnail sizes
- PHImageManager target size reduced from 960×960 to 480×480.
- Delivery mode changed to `.opportunistic`, resize mode to `.fast`.
- AVAssetImageGenerator capped at 480×480.
- JPEG quality reduced to 0.8.

### 9. Blob cleanup on deletion
- `deleteClip` and `deleteTape` schedule background cleanup of the associated blob files via `TapePersistenceActor.deleteBlobs`.

## Key UI components used
- `TapesListView` (loading guard)
- `ThumbnailView` / `ClipCarousel` (identity keys updated to use `hasThumbnail`)

## Data flow
- `TapePersistenceActor.save()`: extracts blobs → writes files → encodes stripped JSON.
- `TapePersistenceActor.load()`: decodes JSON → migrates inline blobs if present → returns clips with nil blob fields.
- `Clip.thumbnailImage`: NSCache → in-memory Data → file on disk.
- `Clip.resolvedImageData`: in-memory Data → file on disk.

## Testing or QA considerations
- Fresh install: verify no empty-state flash; tapes appear immediately.
- Upgrade from previous version: verify thumbnails survive migration (first load migrates blobs to files, second load reads from files).
- Delete a tape and verify blob files are cleaned up (`Documents/clip_media/`).
- Import 30+ clips in a batch and verify the UI stays responsive throughout.
- Kill and relaunch mid-import; confirm no orphaned state.

## Related tickets or links
- None
