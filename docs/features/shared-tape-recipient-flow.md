# Shared Tape Recipient Flow

## Summary

When a user opens a share link, the app downloads all clips from R2, builds a real `Tape` object with `ShareInfo` metadata, and adds it to the local tape store. Shared tapes appear in the "Shared" tab as normal tape cards — identical to user-created tapes.

## Purpose & Scope

Replaces the previous bespoke `SharedTapeDetailView` with the standard tape experience. Recipients see the same `TapeCardView` component (with thumbnail timeline, FAB, and playback controls) that they see for their own tapes.

## Key UI Components

- **`SharedDownloadProgressOverlay`** — mirrors `ImportProgressOverlay` (circular progress ring, cancel button) shown during clip downloads.
- **`SharedTapesView`** — renders `tapesStore.sharedTapes` using `TapeCardView`, the same card component used in the "My Tapes" tab.
- **`TapeCardView`** — existing tape card with thumbnail timeline, title, and action icons.

## Data Flow

1. **Share link opened** → `TapesApp.handleIncomingURL` extracts the share ID.
2. **`NavigationCoordinator.handleShareLink`** sets `pendingSharedTapeId` and switches to the Shared tab.
3. **`SharedTapesView`** observes `pendingSharedTapeId` and starts `SharedTapeDownloadCoordinator`.
4. **`SharedTapeDownloadCoordinator`**:
   - Calls `api.resolveShare(shareId:)` to validate access and get the tape ID.
   - Calls `api.getManifest(tapeId:)` to fetch clip metadata.
   - Downloads each clip and thumbnail from R2 presigned URLs to local cache.
   - Builds `Clip` objects from downloaded data.
   - Constructs a `Tape` with `ShareInfo` and adds it via `tapesStore.addSharedTape()`.
5. **Result**: The tape appears as a normal `TapeCardView` in the Shared tab, persisted locally.

## Model Changes

- **`ShareInfo`** (new struct on `Tape`): Holds `shareId`, `ownerName`, `mode`, `expiresAt`, `remoteTapeId`.
- **`Tape.isShared`**: Computed property — `true` when `shareInfo` is non-nil.
- **`TapesStore.sharedTapes`** / **`TapesStore.myTapes`**: Filtered computed properties over the single `tapes` array.

## Removed Components

- `SharedTapeDetailView` — replaced by standard `TapeCardView`.
- `SharedTapeBuilder` — logic moved into `SharedTapeDownloadCoordinator`.

## Upload Improvements

- Retry logic (3 attempts with exponential backoff) for R2 uploads.
- Increased upload timeout (300s request / 600s resource).
- Video export via `AVAssetExportSession` instead of `requestAVAsset` for more reliable PHAsset access.

## Testing / QA Considerations

- Share a tape with clips → recipient opens link → download overlay appears → tape card appears in Shared tab.
- Verify play button on shared tape works correctly.
- Verify shared tape persists after app restart.
- Test with expired share links (should show error).
- Test upload of large videos (>100 MB) — verify retry logic and timeout handling.
