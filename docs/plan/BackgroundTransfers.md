# Background Transfers — Implementation Plan

## Summary

Replace in-process `URLSession` uploads and downloads with iOS background transfer service so that large media transfers survive app suspension, termination, and device lock.

## Problem

Today, all R2 uploads (`ShareUploadCoordinator`) and downloads (`SharedTapeDownloadCoordinator`) run inside the app process using `URLSession.shared`. When the user backgrounds the app:

1. A `BGContinuedProcessingTask` provides a time budget for the Dynamic Island. When that budget expires, the expiration handler calls `setTaskCompleted(success: false)` — the Dynamic Island shows "Failed".
2. A UIKit `beginBackgroundTask` fallback gives ~30 seconds of extra execution. If the transfer hasn't finished, iOS suspends the process and the transfer dies.
3. The transfer only completes if the user returns to the app before the process is suspended.

This is a data-integrity risk for users on slow connections or with large tapes (66+ clips, hundreds of MB).

The same vulnerability exists in `ExportCoordinator` and `CollabSyncCoordinator`, but export is local CPU work (fast), and collab sync composes the upload/download coordinators (so fixing those fixes collab sync too).

## Solution

Use `URLSession` with a **background configuration**. The OS daemon handles the actual HTTP transfers outside the app process. Transfers continue even if the app is suspended, killed, or the device is locked and rebooted.

## Architecture

### Per-clip upload flow today

```
1. POST /clips           → get presigned R2 URLs     (small JSON, fast)
2. Resolve clip data     → read from Photos library   (local I/O)
3. PUT to R2             → upload media file           (LARGE, SLOW)
4. PUT to R2             → upload thumbnail            (small-medium)
5. PUT to R2             → upload Live Photo movie     (medium, conditional)
6. POST /clips/:id/uploaded → confirm upload          (small JSON, fast)
```

Steps 1, 6 are lightweight API calls (a few KB of JSON). They need the app to be alive, but they complete in under a second.

Steps 3, 4, 5 are the heavy R2 transfers — the ones that need background session support.

Step 2 is local I/O — fast, no network.

### Per-clip upload flow after this change

```
1. POST /clips           → in-process session (fast)
2. Resolve clip data     → write to temp file on disk
3. PUT to R2             → background upload task (fromFile:)
4. PUT to R2             → background upload task (thumbnail)
5. PUT to R2             → background upload task (Live Photo movie)
   ↳ Steps 3-5 survive app suspension
   ↳ On completion, iOS wakes the app and calls the delegate
6. POST /clips/:id/uploaded → in-process session (fast)
7. Next clip → back to step 1
```

### Per-clip download flow after this change

```
1. Background download task (from R2 URL)
   ↳ Survives app suspension
   ↳ On completion, iOS wakes the app with the temp file
2. Save to Photos library (local)
3. POST /clips/:id/downloaded → in-process session (fast)
4. Next clip → back to step 1
```

### Key constraint

`URLSession` background transfers require **file-based** uploads (`uploadTask(with:fromFile:)`) — not in-memory `Data`. So step 2 writes clip data to a temp file before handing it to the background session.

### Presigned URL expiry

R2 presigned URLs default to 1 hour. A clip whose presigned URL was obtained in step 1 will still be valid even if the background transfer is delayed by minutes. If the transfer spans longer than 1 hour (extremely unlikely per-clip), the PUT will fail and the retry logic will re-request a fresh URL.

## New files

### `Tapes/Core/Networking/BackgroundTransferManager.swift`

Single class that owns the background `URLSession`.

- Conforms to `URLSessionDelegate`, `URLSessionDownloadDelegate`, `URLSessionTaskDelegate`.
- Has a stable session identifier (`"com.studiomorph.tapes.transfers"`).
- Maintains an in-memory dictionary mapping `taskIdentifier → TransferContext` (what clip this transfer belongs to, what type: media/thumbnail/movie, what to do on completion).
- Persists a lightweight JSON manifest (`Application Support/transfer_manifest.json`) so the mapping survives app relaunch.
- On `urlSession(_:downloadTask:didFinishDownloadingTo:)` — moves the file to a stable location, notifies the download coordinator.
- On `urlSession(_:task:didCompleteWithError:)` — for uploads, notifies the upload coordinator that the PUT finished (success or failure).
- On `urlSessionDidFinishEvents(forBackgroundURLSession:)` — calls the system completion handler stored by `AppDelegate` (required by Apple).
- Provides `func uploadFile(at:to:contentType:context:)` and `func downloadFile(from:context:)` methods that return immediately after enqueuing.

### `Tapes/Core/Networking/TransferManifest.swift`

Codable struct for the persistent manifest:

```
struct TransferEntry: Codable {
    let taskIdentifier: Int
    let clipId: String
    let tapeId: String
    let transferType: TransferType  // .media, .thumbnail, .livePhotoMovie, .download
    let presignedConfirmUrl: String?  // stored so we can confirm after wake
}
```

Written atomically after every enqueue/dequeue. Lightweight — a few KB even for 66 clips.

## Modified files

### `Tapes/AppDelegate.swift`

Add `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. This is called by iOS when the app is relaunched to deliver background transfer results. Stores the `completionHandler` and tells `BackgroundTransferManager` to reconnect.

### `Tapes/Core/Networking/ShareUploadCoordinator.swift`

- `uploadClip` changes:
  - After `resolveClipData`, write the data to a temp file instead of holding it in memory.
  - Call `BackgroundTransferManager.shared.uploadFile(at:to:contentType:context:)` instead of the current `uploadToR2` in-memory PUT.
  - Use `withCheckedContinuation` or `AsyncStream` to await the transfer completion callback from the manager.
  - Same for thumbnail and Live Photo movie uploads.
- Remove `uploadSession` (the static in-process URLSession).
- Remove `uploadToR2` (replaced by background transfer).
- `handleBackgroundTaskExpiration`: stop calling `setTaskCompleted(success: false)`. The transfers survive without the continued task. Let the continued task stay alive (or nil it without reporting failure).
- `finishUpload` stays the same — called when all clips are confirmed.

### `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift`

- `downloadClip` changes:
  - Replace `session.download(for:)` with `BackgroundTransferManager.shared.downloadFile(from:context:)`.
  - Await the completion callback to get the temp file URL.
  - Rest of the method (save to Photos, confirm download) stays the same.
- Remove `URLSession.shared` usage for downloads.

### `Tapes/Export/ExportCoordinator.swift`

- `handleBackgroundTaskExpiration`: same fix — stop reporting false failure. Export is local so this is cosmetic, but keeps the pattern consistent.

### `Tapes/Core/Networking/CollabSyncCoordinator.swift`

- `handleBackgroundTaskExpiration`: same fix. Collab sync composes the upload/download coordinators, so the transfer resilience comes for free.

### `Tapes/TapesApp.swift`

- Initialise `BackgroundTransferManager.shared` early in `init()` so the background session reconnects on relaunch.

## What does NOT change

- **Server/API** — no changes. Same HTTP endpoints, same presigned URLs.
- **R2** — same PUT/GET. R2 doesn't know or care about the client's session type.
- **Upload/download sequencing** — clips still upload one at a time in order. The loop structure in the coordinators stays the same; only the HTTP transfer step changes.
- **Retry logic** — the `withRetry` wrapper still applies to the API calls. The background session has its own retry behaviour for transient network failures.
- **Progress UI** — `completedClips` / `totalClips` still drives the progress bar. The background transfer manager calls back per-transfer completion, and the coordinator increments `completedClips` exactly as before.
- **Dynamic Island** — `BGContinuedProcessingTask` still submitted for the visual indicator. But it's decoupled from transfer survival — the transfer lives regardless.

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Background session delegate not called if session identifier changes between builds | Medium | Use a fixed string identifier, never change it |
| Temp files accumulate if app is killed mid-transfer | Low | Clean up stale temp files on launch (check manifest for orphans) |
| Presigned URL expires before background transfer starts | Very low | R2 URLs last 1 hour; per-clip transfers take seconds. Retry logic re-requests if expired |
| Memory pressure from writing large video clips to temp files | Low | Write one clip at a time (already sequential). Temp file is deleted after the background task picks it up |
| iOS may delay background transfers on cellular if the system is under pressure | Low | Apple behaviour; nothing we can do. The transfer will eventually complete. Progress updates when it does |

## Verification steps

1. **Small tape (3 clips), Wi-Fi**: Share → background the app immediately → verify Dynamic Island shows progress → verify all clips uploaded successfully → re-open app → completion dialog appears.
2. **Large tape (20+ clips), cellular**: Same flow. Verify uploads continue even if Dynamic Island expires. Verify all clips present on server after completion.
3. **App killed during upload**: Share → background → force-quit from app switcher → relaunch. Verify in-flight transfers resume and complete. Verify manifest picks up where it left off.
4. **Download (shared tape)**: Open a shared tape link → background the app → verify download completes in background → notification on completion.
5. **Cancel during transfer**: Start upload → cancel. Verify background tasks are cancelled and temp files cleaned up.
6. **No network → network restored**: Start upload → airplane mode → wait → restore network. Verify transfer resumes automatically (iOS handles this for background sessions).
7. **Export (regression)**: Export a tape → background the app → verify export completes. Dynamic Island should show success, not failure.

## Rollback

Revert to commit `692a759`. No server changes to undo. All changes are iOS-only.

## Decisions

1. **Retry on presigned URL expiry**: If a background PUT to R2 returns 403 (expired URL), auto-retry once with a freshly requested presigned URL. If the retry also fails, surface the error to the user.

2. **Cellular uploads toggle**: Add an "Allow Cellular Uploads" toggle to Preferences (Account → Settings → Preferences), defaulted to **on** (current behaviour preserved). When off, the background session's `allowsCellularAccess` is set to `false` — iOS will hold transfers until Wi-Fi is available. This ships with the background transfer work, not post-launch.

## Modified files (additional)

### `Tapes/Views/Settings/PreferencesView.swift`

- Add "Allow Cellular Uploads" toggle, backed by `@AppStorage("allowCellularUploads")` defaulting to `true`.
- When toggled, notify `BackgroundTransferManager` to update the session configuration.

### `Tapes/Core/Networking/BackgroundTransferManager.swift` (addendum)

- Read `UserDefaults.standard.bool(forKey: "allowCellularUploads")` when creating the background session configuration.
- Set `config.allowsCellularAccess` accordingly.
- Expose a method to recreate the session with updated cellular policy when the toggle changes (only affects new transfers; in-flight transfers keep their original policy).
