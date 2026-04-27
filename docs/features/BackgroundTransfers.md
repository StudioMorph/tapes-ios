# Background Transfers

Resilient upload and download of clip media via iOS background URL sessions, using a **batch-first architecture** that queues all transfers with the OS daemon upfront.

## Purpose & Scope

All R2 uploads (share, contribute, collab sync) and downloads (shared-tape import) use a `URLSession` with a **background configuration**. The OS daemon (`nsurlsessiond`) handles the HTTP transfers outside the app process, so they survive app suspension, termination, device lock, and reboot.

### Batch Upload Flow

Uploads use a **prepare → submit all → confirm** pattern:

1. One API call (`POST /tapes/:id/prepare-upload`) creates all clip D1 records and returns presigned URLs for every file.
2. All clip data is resolved (Photos library reads) and written to temp files while the app is in the foreground.
3. All upload tasks (media + thumbnails + Live Photo movies) are submitted to the background `URLSession` at once.
4. The OS daemon executes all uploads — the app can be killed, and transfers continue.
5. When all uploads finish, one API call (`POST /tapes/:id/confirm-batch`) confirms them all and sends a single push notification.

This replaces the previous sequential per-clip loop where each clip required its own API calls (createClip, confirmUpload) with the app alive.

### Concurrent Download Flow

Downloads submit all background download tasks concurrently via `withTaskGroup`. Each `downloadFile` call creates a background URLSession task immediately; the OS daemon manages them all concurrently. Post-download processing (save to Photos, build Clip objects) happens as results arrive.

## Key Components

| File | Role |
|------|------|
| `Core/Networking/BackgroundTransferManager.swift` | Singleton owning the background `URLSession`. Supports both single-file async methods and batch submission with completion callbacks. Tracks batch progress and per-task context. |
| `Core/Networking/TransferManifest.swift` | Persistent JSON manifest tracking in-flight transfers with batch grouping, status tracking (pending/completed/failed), and cloud URL storage. Survives app termination. |
| `Core/Networking/TapesAPIClient.swift` | `prepareUploadBatch` and `confirmUploadBatch` methods for the new batch API endpoints. |
| `AppDelegate.swift` | Implements `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to reconnect the session when iOS relaunches the app. |
| `Core/Networking/ShareUploadCoordinator.swift` | Uses batch prepare → submit all → confirm flow for both `ensureTapeUploaded` and `contributeClips`. |
| `Features/Import/SharedTapeDownloadCoordinator.swift` | Uses concurrent `withTaskGroup` to submit all downloads at once. |

## Server Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /tapes/:id/prepare-upload` | Creates all clip records + returns presigned URLs (2-hour expiry) in one call. Max 200 clips. |
| `POST /tapes/:id/confirm-batch` | Confirms all uploaded clips, creates download tracking, sends push. Idempotent. |

Both are additive — the old per-clip `POST /clips` and `POST /clips/:id/uploaded` endpoints remain for backward compatibility and the single-clip contribute flow.

## Dynamic Island Behaviour

`BGContinuedProcessingTask` is submitted for the Dynamic Island progress display. Progress updates as delegate callbacks arrive. When the system's time budget expires, the expiration handler calls `setTaskCompleted(success: true)` with subtitle "Continuing in background…". The transfers continue independently via the background session. A local notification fires on completion.

## Cellular Uploads Toggle

"Allow Cellular Uploads" toggle in Preferences controls `URLSessionConfiguration.allowsCellularAccess` on the background session. Defaults to **on**. When off, the OS holds transfers until Wi-Fi is available.

## Presigned URL Expiry

Batch-generated URLs use a **2-hour** expiry (vs 1 hour for single-clip). A 66-clip tape at 10 MB/clip = ~660 MB, which takes ~44 minutes on 2 Mbps cellular. The 2-hour window provides comfortable margin. If a URL does expire (HTTP 403), the retry logic can re-prepare just the failed clips.

## Testing / QA Considerations

- **Small tape, foreground**: Share 3-clip tape → verify all uploaded → confirm succeeds.
- **Large tape, background immediately**: Share 30+ clip tape → background immediately → verify Dynamic Island → verify all clips on server.
- **Force-quit during upload**: Share → background → force-quit → wait → relaunch → verify batch confirm sent → completion.
- **Cellular, slow**: Share on cellular → background → verify transfers continue → all clips arrive.
- **Cellular toggle off**: Toggle off → share → verify transfers held → connect Wi-Fi → verify resume.
- **Download, large tape**: Open shared link → background → verify all clips downloaded → Photos library updated.
- **Cancel mid-batch**: Start 30-clip upload → cancel after 10 → verify all tasks cancelled.
- **Export regression**: Export → background → verify Dynamic Island doesn't show "Failed."

## Related

- `docs/plan/BatchBackgroundTransfers.md` — approved batch implementation plan
- `docs/plan/BackgroundTransfers.md` — original background transfers plan
- `docs/features/sharing-with-cloud.md` — overall sharing architecture
