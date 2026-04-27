## Upload Pipeline Optimisation

## Summary

Reshapes the share-upload pipeline in `ShareUploadCoordinator` to run Photos library extraction off the main thread, take a faster path for local videos, overlap extraction and upload, and stream Live Photo components directly from disk. No change to backend contract, `BGContinuedProcessingTask`, or retry behaviour.

## Purpose & scope

- **Purpose:** shorten per-clip processing time and remove the main-thread blocking that was contributing to UI stalls and the `Missing prefetched properties… Fetching on demand on the main queue` warning during uploads — particularly on tapes that contain Live Photos.
- **Scope:** `Tapes/Core/Networking/ShareUploadCoordinator.swift`. No changes to `TapesAPIClient`, the Worker, or the share modal UI.
- **Non-goals:** solving `BGContinuedProcessingTask` early-expiry (tracked separately). No change to which bytes are uploaded for any clip type.

## Key UI components used

None changed. Progress dialog and completion dialog behave exactly as before. `statusMessage`, `progress`, and the iOS 26+ Dynamic Island progress continue to update per clip.

## Data flow (ViewModel → Model → Persistence)

`ShareUploadCoordinator.ensureTapeUploaded` / `contributeClips` → per-clip loop with extract-ahead pipelining:

1. `prepareClip(_:)` — runs off-main (`nonisolated static`); produces a `PreparedClip` with either in-memory `Data` or a temp-file `URL` plus a list of temp files to clean up.
2. `uploadPrepared(_:prepared:tapeId:api:)` — runs off-main; calls `createClip`, uploads the primary payload (data or file stream), uploads paired Live Photo video from disk, uploads the thumbnail, calls `confirmUpload`.
3. `cleanupTempFiles(_:)` — removes any temp files the prepared clip created (Live Photos only).

The lookahead pattern:

```
prefetch = Task.detached { prepareClip(clips[0]) }
for i in 0..<clips.count:
    current = prefetch
    prefetch = (i+1 < count) ? Task.detached { prepareClip(clips[i+1]) } : nil
    upload prepared from current; cleanup
```

So while clip N is uploading over the network, clip N+1's Photos-library extraction is already running on the cooperative pool.

### Extraction paths

| Clip type | Extraction API | Payload |
|---|---|---|
| Live Photo (iCloud or local) | `PHAssetResourceManager.writeData` for `.photo` and `.pairedVideo` | Two temp files (streamed to R2) |
| Regular video (local, unedited) | `PHImageManager.requestAVAsset` → `AVURLAsset.url` → `Data(contentsOf:)` | In-memory `Data` |
| Regular video (iCloud or edited) | Fallback: `PHImageManager.requestExportSession` + `AVAssetExportSession` passthrough | In-memory `Data` |
| Regular photo | `PHImageManager.requestImageDataAndOrientation` | In-memory `Data` |
| Local sandbox file (`clip.localURL` exists) | `Data(contentsOf:)` on the existing sandbox file | In-memory `Data` |

### Upload overloads

- `uploadToR2(url:data:contentType:)` — used for in-memory payloads (regular photos, regular videos, thumbnails).
- `uploadToR2(url:fileURL:contentType:)` — used for Live Photo components. Streams from the already-on-disk temp file via `URLSession.upload(for:fromFile:)`; no additional file→Data round trip.

## Testing or QA considerations

- Upload a tape containing Live Photos, regular photos, and regular videos. All three should succeed end-to-end.
- Watch Xcode console during the upload: the `Missing prefetched properties… Fetching on demand on the main queue` warning should no longer appear.
- Share a Live Photo-heavy tape to another device; confirm Live Photos reconstruct on the receiver (content identifier preserved).
- Force an iCloud-only video into a tape (delete local copy, leave iCloud original). Confirm the upload still completes — this exercises the `requestExportSession` fallback.
- Upload a tape with 10+ clips. Clip N+1's extraction should visibly overlap with clip N's upload (progress messaging stays smooth, total time shorter than strict sequential).
- Cancel an upload mid-flight; verify no orphan temp files are left in `tmp/LivePhotoExport/` after the next launch.

## Related tickets or links

- Plan: `docs/plan/UploadPipelineOptimisation.md`
- Preceding feature docs: `docs/features/sharing-with-cloud.md`, `docs/features/LivePhotos.md`, `docs/features/BackgroundDownload.md`
