# Upload Pipeline Optimisation

**Status:** implemented (initial pass + file-streaming follow-up). See `docs/features/UploadPipelineOptimisation.md` for the shipped behaviour.

> **Follow-up (post-merge):** the initial implementation kept regular videos and sandbox imports on the `Data`-buffer path. A second pass extended the file-URL overload to cover them as well, eliminating two more `Data(contentsOf:)` round-trips and consolidating the Live Photo flow to a single `PHAsset.fetchAssets` call. See "Follow-up" section at the bottom.
**Scope:** iOS only. `ShareUploadCoordinator.swift`.
**Risk:** low-medium. All changes are additive or safe refinements to the existing pipeline. No API contract changes, no backend changes.
**Starting point:** `ShareUploadCoordinator.swift` as committed at `692a759`.

---

## Problem

The upload pipeline at `692a759` works but has three compounding inefficiencies that are especially bad for Live Photos (the clip type that's been causing the most failures):

1. **All Photos library work runs on the main thread.** The extraction functions are `private static func` on a `@MainActor` class, making them main-actor-isolated. Every `PHImageManager.requestImageDataAndOrientation`, `PHAssetResourceManager.writeData`, and `AVAssetExportSession.export` call blocks the main thread. The log `Missing prefetched properties... Fetching on demand on the main queue, which may degrade performance` confirms this — iOS is explicitly telling us we're doing heavy Photos work on the main thread.

2. **Videos are exported when they don't need to be.** `requestExportSession(forVideo:exportPreset:AVAssetExportPresetPassthrough)` spins up the full AVFoundation export pipeline, writes a temp file, which is then read back into `Data`, deleted, and uploaded. Double the disk I/O for zero transcoding benefit.

3. **Extraction and upload are fully sequential per clip.** While clip N uploads to R2 (seconds of network I/O), the CPU and disk are idle waiting. The next clip's extraction can't start until the current clip's upload finishes.

4. **(Live Photos only) Upload flow is inefficient.** Live Photo extraction already writes to a temp file, but then we read the file back into `Data`, delete the file, and upload from memory. That's write → read → upload — three full data passes per Live Photo component.

---

## Why Live Photos suffer the most

Every Live Photo does:
- Two `PHAssetResourceManager.writeData` calls (photo + paired video)
- Each call triggers FIGSANDBOX retries (the `<<<< FIGSANDBOX >>>> signalled err=-17507` noise)
- Both calls block the main thread
- Both are followed by read-back-into-Data + file deletion
- Both result in two separate R2 uploads (photo + paired video to two different URLs)

A Live-Photo-heavy tape triggers every inefficiency simultaneously. Regular photos and videos are faster and lighter by comparison.

---

## Solution: four targeted changes

### 1. `nonisolated static` on all extraction functions

**Change:** Add `nonisolated` to:
- `uploadClip`
- `resolveClipData`
- `resolveLivePhotoMovieData`
- `exportLivePhotoImageResource`
- `exportPHAssetData`
- `uploadToR2`
- `uploadSession` (the static `URLSession`)

**Effect:** Photos library extraction runs on a background thread instead of blocking the main actor. Main thread stays responsive. Eliminates the `Missing prefetched properties... Fetching on demand on the main queue` warning.

**Safety:** These functions don't touch `@MainActor` state — they operate entirely on their inputs and Photos framework calls. Photos APIs are thread-safe. This is the same change we made earlier in the session that was reverted with everything else.

### 2. `requestAVAsset` for video extraction (with fallback)

**Change:** Replace `PHImageManager.requestExportSession` + `AVAssetExportSession.export` with `PHImageManager.requestAVAsset`.

**New video flow:**
```
requestAVAsset(forVideo: asset, options: ...)
  → AVAsset? (may be AVURLAsset for local assets)
  → if AVURLAsset → read Data(contentsOf: avUrlAsset.url) directly
  → else (iCloud, composition) → fall back to export session (current approach)
```

**Effect:**
- Local videos: 1 disk read instead of export-write + read-back. Half the I/O, no AVFoundation export pipeline spin-up.
- iCloud videos: same as today — the fallback handles the edge case where `AVURLAsset` cast fails.

**Safety:** The fallback to the current export session path means iCloud and edited videos work exactly as before. Only local unedited videos take the faster path.

### 3. Extract-ahead pipelining

**Change:** While clip N is uploading, start extracting clip N+1. Use `async let` inside the per-clip loop to overlap the next clip's extraction with the current clip's network upload.

**Conceptual flow:**
```
For each clip index i:
    prefetched_next = async let resolveClipData(clips[i+1])  (if i+1 exists)
    upload(current_data)
    current_data = await prefetched_next
```

**Effect:** On a tape with many clips, the total time shortens by the amount of disk I/O that was previously waiting idle during network upload. Realistic savings: 20-40% on tapes with a mix of clip types.

**Safety:**
- Only 1 lookahead. No unbounded concurrency.
- If clip N fails to upload, clip N+1's prefetched data is discarded (minor wasted work, no correctness impact).
- Cancellation is honoured — if the upload task is cancelled, the lookahead task is cancelled too.

### 4. Live-Photo-specific: upload directly from temp file

**Change:** For Live Photos only (which already write to a temp file during extraction), upload from the file URL instead of reading into `Data`.

**Current Live Photo flow:**
```
writeData → temp file
Data(contentsOf: temp file)
delete temp file
uploadToR2(data: Data)
```

**New Live Photo flow:**
```
writeData → temp file
uploadToR2(fileURL: temp file)  ← URLSession.upload(for:fromFile:) streams from disk
delete temp file
```

**Effect:** One pass instead of three. Near-zero memory for the photo + paired video uploads (the two biggest individual files in a Live Photo-heavy tape).

**Implementation:** Add a `uploadToR2(url:fileURL:contentType:)` overload that uses `URLSession.upload(for:fromFile:)`. Keep the existing `Data`-based overload for thumbnails, regular photos, and regular videos (those don't already have a temp file).

**Safety:** This is precisely what I tried in the earlier (reverted) change *for the wrong clip types*. Applied only to Live Photos — where the temp file already exists from `writeData` — it's strictly better than the current flow. No change to which bytes get uploaded.

---

## What does NOT change

- **`BGContinuedProcessingTask`** — untouched.
- **`beginBackgroundTask` / `endBackgroundTask`** — untouched.
- **Progress reporting** — `updateContinuedTaskProgress()` and progress dialog logic stay the same.
- **API calls** — `createClip`, `confirmUpload`, `declareUploadBatch`, `deleteClip` unchanged.
- **Regular photo extraction** — still uses `PHImageManager.requestImageDataAndOrientation`. Fast, correct API.
- **Regular video extraction (iCloud/edited)** — still uses `AVAssetExportSession` passthrough as fallback.
- **Live Photo extraction** — still uses `PHAssetResourceManager.writeData`. Correct API for preserving metadata.
- **Retry logic** — `withRetry(maxAttempts: 3)` unchanged.
- **Backend** — no changes.

---

## Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `requestAVAsset` returns a non-`AVURLAsset` for some local videos (e.g. edited ones) | Medium for edited videos, very low for untouched camera videos | Fallback to existing `requestExportSession` path when cast fails. Zero regression from current behaviour. |
| Pipelining wastes work if a clip fails | Low — only wastes the next-clip extraction, which would have run anyway | Minor. Extraction cost is small vs upload cost. |
| Cancelling mid-upload leaves a pending prefetch Task | Low | Structured `async let` inside the same scope gets cancelled automatically when the parent task is cancelled. |
| `nonisolated static` breaks something that silently depended on main-thread execution | Very low — the functions don't touch main-actor state | We already ran these as `nonisolated static` earlier in the session and the build succeeded. Revert if any runtime issue appears. |
| Live Photo `URLSession.upload(for:fromFile:)` behaves differently from `upload(for:from:)` | Very low — same API, same bytes, just streamed | Tested pattern, standard URLSession usage. Server sees the same PUT request either way. |

---

## Verification

1. **Build** — zero compile errors.
2. **Main thread check** — confirm the `Missing prefetched properties... Fetching on demand on the main queue` warning is gone from logs during upload.
3. **Upload a tape with regular photos + regular videos** — verify videos use the `requestAVAsset` path (add a single info log to distinguish). Upload completes successfully.
4. **Upload a tape with Live Photos** — verify each Live Photo completes (both the photo and the paired video parts). Confirm on the receiving device that Live Photos reconstruct correctly (metadata preserved).
5. **Upload a large tape (20+ clips)** — observe whether per-clip timing is more consistent and the total upload time decreases compared to the baseline at `692a759`.
6. **Backgrounding** — upload while backgrounding the app. Verify completion notification arrives.
7. **iCloud assets** — upload a clip with an iCloud-only asset to confirm the network-access path still works.

---

## Files touched

| File | Change |
|---|---|
| `Tapes/Core/Networking/ShareUploadCoordinator.swift` | Mark extraction/upload functions `nonisolated static`. Add `requestAVAsset` path for videos with export-session fallback. Add `async let` lookahead pipelining to `uploadClip` loop in both `ensureTapeUploaded` and `contributeClips`. Add `uploadToR2(url:fileURL:contentType:)` overload. Route Live Photo uploads through the file-based overload. |

---

## Follow-up: extend file-streaming to all file-backed payloads

The initial implementation left two paths still loading entire files into RAM before handing them to URLSession, and one redundant PhotoKit fetch. After observing real-device upload behaviour we applied three further refinements, all in `ShareUploadCoordinator.swift`.

### Waste #1 — Regular videos read into `Data` before upload

`exportVideoData(phAsset:)` returned `Data` for both the fast (`requestAVAsset`) and the fallback (`requestExportSession`) paths. For a 200 MB video that meant a full `Data(contentsOf:)` pass into RAM, then URLSession copied the buffer into its send buffer, and only then could the first byte hit the network.

**Fix:** Replace `exportVideoData` with `exportVideoToFile(phAsset:) -> (url: URL, ownedTempFiles: [URL])`. The fast path returns the `AVURLAsset.url` directly (PhotoKit owns the file, no cleanup). The fallback writes to a temp `.mp4` we own and clean up. Both flow through `uploadToR2(url:fileURL:contentType:)`. URLSession reads chunks off disk and pushes them straight into the TLS socket; memory peak drops from "size of largest video" to "URLSession's internal chunk buffer".

### Waste #2 — Sandbox imports read into `Data` before upload

When `clip.localURL` exists (custom camera capture, video editor output, etc.), `prepareClip` was doing `Data(contentsOf: url)` and uploading the buffer. Same overhead as Waste #1.

**Fix:** Pass the URL straight to `uploadToR2(url:fileURL:contentType:)`. Crucially, `clip.localURL` is **not** added to `tempFiles` — the file lives in the app's persistent imports store and must outlive the upload.

### Waste #3 — Live Photos fetched twice

`exportLivePhotoPhotoToFile(identifier:)` and `exportLivePhotoMovieToFile(identifier:)` each called `fetchPHAssetWithRetry`, doing two synchronous `PHAsset.fetchAssets` queries per Live Photo. Cheap individually but a multiplier on Live-Photo-heavy tapes.

**Fix:** Inline the Live Photo branch in `prepareClip`: one `fetchPHAssetWithRetry` → one `PHAssetResource.assetResources(for:)` → two `writeAssetResource` calls. The `exportLivePhotoPhotoToFile` / `exportLivePhotoMovieToFile` helpers were removed; the writing helper (`writeAssetResource`) is unchanged.

### Cancellation cleanup

The orphan prefetch task (extraction of clip N+1 when the loop ends or is cancelled before consuming it) now has its temp files cleaned up. Without this, a cancelled upload of an export-session video could leave a `.mp4` in `tmp/` until the next system sweep.

### Verification (follow-up)

- Build clean on iOS Simulator (iPhone 16 Pro, iOS 26 SDK, deployment target 18.2).
- Lints clean on `ShareUploadCoordinator.swift`.
- No backend or API contract changes.
- Behavioural acceptance: the same bytes are uploaded for every clip type; only the path bytes take from PhotoKit/disk to URLSession changes.
