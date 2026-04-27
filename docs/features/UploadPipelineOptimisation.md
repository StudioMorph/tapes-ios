## Upload Pipeline Optimisation

## Summary

Reshapes the share-upload pipeline in `ShareUploadCoordinator` to run Photos library extraction off the main thread, take a faster path for local videos, overlap extraction and upload, and stream **every file-backed payload** directly from disk to R2 (videos, sandbox imports, both Live Photo resources). Only in-memory buffers we already own (still photos resolved by PhotoKit, thumbnails) are uploaded as `Data`. No change to backend contract, `BGContinuedProcessingTask`, or retry behaviour.

## Purpose & scope

- **Purpose:** shorten per-clip processing time, drop memory peaks (no more 50–200 MB `Data` buffers held while a video uploads), and start the network transfer earlier (URLSession can start sending after the first disk read instead of waiting for the whole file to land in RAM).
- **Scope:** `Tapes/Core/Networking/ShareUploadCoordinator.swift`. No changes to `TapesAPIClient`, the Worker, or the share modal UI.
- **Non-goals:** solving `BGContinuedProcessingTask` early-expiry (tracked separately). No change to which bytes are uploaded for any clip type.

## Key UI components used

None changed. Progress dialog and completion dialog behave exactly as before. `statusMessage`, `progress`, and the iOS 26+ Dynamic Island progress continue to update per clip.

## Data flow (ViewModel → Model → Persistence)

`ShareUploadCoordinator.ensureTapeUploaded` / `contributeClips` → per-clip loop with extract-ahead pipelining:

1. `prepareClip(_:)` — runs off-main (`nonisolated static`); produces a `PreparedClip` with either an in-memory `Data` (small still-photo buffers only) or a `file(URL)` reference, plus a list of temp files the upload step must clean up. Only files we created (Live Photo resources, fallback export-session videos) appear in `tempFiles`; URLs that belong to PhotoKit (`AVURLAsset.url`) or to the app's persistent imports store (`clip.localURL`) are streamed but never deleted.
2. `uploadPrepared(_:prepared:tapeId:api:)` — runs off-main; calls `createClip`, uploads the primary payload (data **or** file stream), uploads paired Live Photo video from disk, uploads the thumbnail, calls `confirmUpload`.
3. `cleanupTempFiles(_:)` — removes any temp files the prepared clip created. Also runs on the cancellation path for the orphan prefetch task so an aborted batch doesn't leave files behind.

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

| Clip type | Extraction API | Payload | Cleanup owner |
|---|---|---|---|
| Live Photo (iCloud or local) | One `PHAsset.fetchAssets` then `PHAssetResourceManager.writeData` for `.photo` and `.pairedVideo` | Two temp files (streamed to R2) | This coordinator |
| Regular video (local, unedited) | `PHImageManager.requestAVAsset` → `AVURLAsset.url` (streamed straight from PhotoKit cache) | File URL | PhotoKit (no cleanup) |
| Regular video (iCloud or edited) | Fallback: `PHImageManager.requestExportSession` + `AVAssetExportSession` passthrough → `.mp4` in `tmp` | File URL | This coordinator |
| Regular photo (PHAsset) | `PHImageManager.requestImageDataAndOrientation` | In-memory `Data` | n/a |
| Local sandbox file (`clip.localURL` exists) | Direct file URL (no read, no copy) | File URL | App's imports store (no cleanup) |
| Image data already in memory (`clip.resolvedImageData`) | Use as-is | In-memory `Data` | n/a |

### Upload overloads

- `uploadToR2(url:data:contentType:)` — used for the small in-memory buffers that we already hold (still photos resolved by PhotoKit, thumbnails). Sets `Content-Length` explicitly.
- `uploadToR2(url:fileURL:contentType:)` — used for **everything backed by a file**: PhotoKit videos (direct or export-session), Live Photo `.photo` and `.pairedVideo`, sandbox imports. Streams via `URLSession.upload(for:fromFile:)`. URLSession reads chunks off disk and pushes them straight into the TLS socket, so memory stays flat regardless of file size and time-to-first-byte drops to milliseconds.

### Per-clip parallelism

Within a single clip the three R2 PUTs (primary payload, paired Live Photo movie, thumbnail) write to independent signed URLs and have no server-side ordering requirement. They run concurrently via `async let`. Wall-clock for a clip becomes "the slowest of the three" instead of "the sum of all three", which roughly halves the upload time for Live Photos (where the photo and paired video are both significant) and is a negligible win for regular clips (the thumbnail is tiny). A throw from any of the three cancels the still-in-flight peers via structured concurrency; `withRetry` then re-runs the whole clip end-to-end exactly as it did under the sequential version.

## Testing or QA considerations

- Upload a tape containing Live Photos, regular photos, and regular videos. All three should succeed end-to-end.
- Watch Xcode console during the upload: the `Missing prefetched properties… Fetching on demand on the main queue` warning should no longer appear.
- Share a Live Photo-heavy tape to another device; confirm Live Photos reconstruct on the receiver (content identifier preserved).
- Force an iCloud-only video into a tape (delete local copy, leave iCloud original). Confirm the upload still completes — this exercises the `requestExportSession` fallback that now writes a temp `.mp4` and streams it from disk.
- Upload a tape with 10+ clips. Clip N+1's extraction should visibly overlap with clip N's upload (progress messaging stays smooth, total time shorter than strict sequential).
- Memory check (Instruments → Allocations): peak resident size during a multi-video tape upload should stay roughly flat; previously it climbed proportional to the largest video being processed.
- Cancel an upload mid-flight; verify no orphan files remain in `tmp/LivePhotoExport/` or in the root of `tmp/` (e.g. `*.mp4` from the export-session fallback) after the next launch.

## Related tickets or links

- Plan: `docs/plan/UploadPipelineOptimisation.md`
- Preceding feature docs: `docs/features/sharing-with-cloud.md`, `docs/features/LivePhotos.md`, `docs/features/BackgroundDownload.md`
