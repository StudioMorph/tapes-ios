# Batch Background Transfers — Implementation Plan

## Goal

Upload or download a tape of any size — 3 clips or 66 — fully in the background. Once the user triggers the action, the transfers complete reliably as long as a network connection exists, even if the app is suspended, terminated, or the device is locked. No size limits, no "probably," no wake-up chains.

---

## Why the current approach falls short

The current implementation uses a background `URLSession` but wraps it in a **sequential, app-dependent loop**:

```
for each clip:
    1. API call: createClip → presigned URL     (needs app alive)
    2. Write clip data to temp file              (needs app alive)
    3. Background upload to R2                   (survives suspension ✓)
    4. API call: confirmUpload                   (needs app alive)
```

Steps 1, 2, and 4 require the app process to be running. The only step that survives backgrounding is step 3 — and only for the *current* clip. For a 66-clip tape, the app must be woken 66 times in a row, each time hoping iOS grants enough execution time to advance to the next clip. This is fragile by design.

Apple's own guidance (WWDC 2023 "Build robust and resumable file transfers," Apple docs on background URL sessions) is explicit:

> **Queue all background transfer tasks upfront while the app is in the foreground. Do not chain them sequentially.**

---

## Solution: batch all transfers upfront

### Upload flow (new)

```
iOS                              Workers API                         R2
 |                                    |                               |
 |  1. POST /tapes                    |                               |
 |  (create tape, unchanged)          |                               |
 |  ────────────────────────────────> |                               |
 |  { tape_id, share_ids }           |                               |
 |  <──────────────────────────────── |                               |
 |                                    |                               |
 |  2. POST /tapes/:id/prepare-upload |                               |
 |  { clips: [ {clip_id, type,       |                               |
 |    duration_ms, ...} × N ] }       |                               |
 |  ────────────────────────────────> |  Generate N presigned URL     |
 |                                    |  sets in a loop               |
 |  { clips: [ {clip_id,             |                               |
 |    upload_url,                     |                               |
 |    thumbnail_upload_url,           |                               |
 |    live_photo_movie_upload_url?    |                               |
 |    } × N ] }                       |                               |
 |  <──────────────────────────────── |                               |
 |                                    |                               |
 |  3. Resolve ALL clip data locally  |                               |
 |     Write each to a temp file      |                               |
 |     Submit ALL upload tasks to     |                               |
 |     background URLSession at once  |                               |
 |     (N media + N thumbnails +      |                               |
 |      K live photo movies)          |                               |
 |  ═══════════════════════════════════════════════════════════════>  |
 |                                    |                               |
 |  ── App can be suspended or killed here. All transfers continue ── |
 |                                    |                               |
 |  4. As each task completes,        |                               |
 |     delegate fires, results        |                               |
 |     collected in TransferManifest  |                               |
 |                                    |                               |
 |  5. When ALL tasks complete:       |                               |
 |     POST /tapes/:id/confirm-batch  |                               |
 |     { clips: [ {clip_id,          |                               |
 |       cloud_url, thumbnail_url,    |                               |
 |       live_photo_movie_url? }      |                               |
 |       × N ] }                      |                               |
 |  ────────────────────────────────> |  Confirm all clips,           |
 |                                    |  create download tracking,    |
 |                                    |  send push notification       |
 |  { confirmed: N,                  |                               |
 |    batch_completed: true }         |                               |
 |  <──────────────────────────────── |                               |
```

**The critical difference:** after step 3, the app plays no role. The OS daemon runs all N×3 transfers concurrently (the system manages how many at a time). Even if the user force-quits the app, the OS continues every transfer. When all transfers finish, iOS relaunches the app in the background, the delegate delivers all results, and the app sends one batch confirm to the server.

### Download flow (new)

Downloads are simpler because `GET /tapes/:id/manifest` already returns all clip URLs at once.

```
iOS                              Workers API                         R2
 |                                    |                               |
 |  1. GET /share/:share_id          |                               |
 |  ────────────────────────────────> |                               |
 |  { tape_id, ... }                 |                               |
 |  <──────────────────────────────── |                               |
 |                                    |                               |
 |  2. GET /tapes/:id/manifest       |                               |
 |  ────────────────────────────────> |                               |
 |  { clips: [{cloud_url, ...}×N] }  |                               |
 |  <──────────────────────────────── |                               |
 |                                    |                               |
 |  3. Submit ALL download tasks to   |                               |
 |     background URLSession at once  |                               |
 |     (N media + K movies +          |                               |
 |      N thumbnails)                 |                               |
 |  <═══════════════════════════════════════════════════════════════  |
 |                                    |                               |
 |  ── App can be suspended or killed here. All transfers continue ── |
 |                                    |                               |
 |  4. As each task completes,        |                               |
 |     delegate fires, file moved     |                               |
 |     to stable location, result     |                               |
 |     tracked in TransferManifest    |                               |
 |                                    |                               |
 |  5. When ALL downloads complete:   |                               |
 |     Save all clips to Photos       |                               |
 |     Build Clip objects             |                               |
 |     Add tape to TapesStore         |                               |
 |     Confirm downloads to server    |                               |
```

---

## Server changes (Cloudflare Worker)

### New endpoint: `POST /tapes/:tape_id/prepare-upload`

Accepts all clip metadata in a single request. For each clip, creates the D1 record and generates presigned R2 URLs. Returns the full set of URLs.

This is functionally identical to calling `POST /tapes/:id/clips` N times, but in a single HTTP round-trip. The presigned URL generation logic (`aws4fetch` / S3 signing) is the same — just called in a loop.

**Request:**
```json
{
  "clips": [
    {
      "clip_id": "uuid-1",
      "type": "video",
      "duration_ms": 8400,
      "trim_start_ms": 0,
      "trim_end_ms": 8400,
      "audio_level": 1.0,
      "motion_style": "ken_burns",
      "image_duration_ms": null,
      "rotate_quarter_turns": null,
      "override_scale_mode": null,
      "live_photo_as_video": null,
      "live_photo_sound": null
    }
  ],
  "batch_type": "invite",
  "mode": "view_only"
}
```

**Response: `200 OK`**
```json
{
  "batch_id": "uuid",
  "clips": [
    {
      "clip_id": "uuid-1",
      "upload_url": "https://...r2.../clips/uuid-1.mp4?X-Amz-...",
      "thumbnail_upload_url": "https://...r2.../thumbs/uuid-1.jpg?X-Amz-...",
      "live_photo_movie_upload_url": null,
      "upload_url_expires_at": "2026-04-27T01:00:00Z",
      "order_index": 0
    }
  ],
  "expected_count": 1
}
```

**Implementation notes:**
- Wraps each clip insert + presigned URL generation in the same D1 transaction the existing `POST /clips` uses.
- Also creates the upload batch record (replaces the separate `POST /upload-batch` call for this flow).
- Presigned URLs use a **2-hour** expiry (up from the current 1 hour) to give large tapes more buffer.
- Rate limit: exempt from the per-clip 30/min limit since it's a single request.
- Max clips per request: 200 (well above any foreseeable tape size; returns 422 if exceeded).

### New endpoint: `POST /tapes/:tape_id/confirm-batch`

Confirms all uploaded clips in a single request. Replaces calling `POST /clips/:id/uploaded` N times.

**Request:**
```json
{
  "clips": [
    {
      "clip_id": "uuid-1",
      "cloud_url": "https://...r2.../clips/uuid-1.mp4",
      "thumbnail_url": "https://...r2.../thumbs/uuid-1.jpg",
      "live_photo_movie_url": null
    }
  ]
}
```

**Response: `200 OK`**
```json
{
  "confirmed": 5,
  "batch_completed": true,
  "tracking_records_created": 15
}
```

**Implementation notes:**
- Loops through clips, updates each D1 record with `cloud_url`, `thumbnail_url`, `live_photo_movie_url`.
- Creates download tracking records for all participants.
- Sends a single consolidated push notification (same logic as existing batch completion).
- Idempotent: re-confirming an already-confirmed clip is a no-op.
- Partial confirms are supported: if only 60 of 66 clips uploaded successfully, the request confirms those 60. The remaining 6 can be retried later.

### Existing endpoints — no changes

- `POST /tapes` — unchanged
- `GET /tapes/:id/manifest` — unchanged (already returns all clip URLs)
- `POST /clips/:id/uploaded` — still exists for single-clip confirms (used by contribute flow)
- `POST /clips/:id/downloaded` — still exists
- `GET /share/:share_id` — unchanged

### Migration / backward compatibility

Both new endpoints are **additive**. The old per-clip `POST /clips` and `POST /clips/:id/uploaded` endpoints remain fully functional. Older app versions continue to work. The new endpoints are only called by the updated iOS client.

---

## iOS changes

### `TapesAPIClient.swift`

Two new methods:

```
func prepareUploadBatch(tapeId:, clips:, batchType:, mode:) async throws -> PrepareUploadResponse
func confirmUploadBatch(tapeId:, clips:) async throws -> ConfirmBatchResponse
```

New response structs:

```
struct PrepareUploadResponse: Decodable
    batchId: String
    clips: [BatchClipUploadInfo]

struct BatchClipUploadInfo: Decodable
    clipId: String
    uploadUrl: String
    thumbnailUploadUrl: String
    livePhotoMovieUploadUrl: String?
    uploadUrlExpiresAt: String
    orderIndex: Int

struct ConfirmBatchResponse: Decodable
    confirmed: Int
    batchCompleted: Bool
    trackingRecordsCreated: Int
```

### `BackgroundTransferManager.swift`

Extend with:

- **Task-to-clip mapping:** a dictionary `[Int: TransferContext]` that maps each `URLSessionTask.taskIdentifier` to the clip it belongs to and the transfer type (media, thumbnail, movie). This replaces the current per-transfer continuations for the batch flow.
- **Batch completion tracking:** a `TransferBatch` struct that tracks how many tasks were submitted, how many have completed (success/failure), and the results for each clip. When all tasks complete, a callback fires.
- **`submitBatchUpload(tasks:completion:)` method:** accepts an array of `(fileURL, remoteURL, contentType, context)` tuples, creates all upload tasks, calls `resume()` on each, and stores the batch context.
- **`submitBatchDownload(urls:completion:)` method:** same pattern for downloads.
- The existing `uploadFile` / `downloadFile` async methods remain for single-transfer use cases (contribute flow, thumbnail downloads).

### `TransferManifest.swift`

Extend `TransferEntry` with:

- `batchId: String?` — groups entries that belong to the same batch.
- `status: TransferStatus` — `.pending`, `.completed`, `.failed`.
- `cloudUrl: String?` — the base URL (without query params) for confirmed uploads.

On relaunch, the manifest tells the app:
1. Which batch was in progress.
2. Which clips within the batch completed successfully (and their cloud URLs).
3. Which clips failed.

The app can then call `confirm-batch` for the successful ones and retry the failed ones.

### `ShareUploadCoordinator.swift`

Replace the sequential loop with:

1. **Prepare phase** (app must be alive — runs in foreground):
   - Compute which clips need uploading (delta logic unchanged).
   - Call `prepareUploadBatch` — one API call, get all presigned URLs.
   - Resolve all clip data and write each to a temp file.
   - Submit all upload tasks to `BackgroundTransferManager` at once.
   - Save the batch context to `TransferManifest`.

2. **Transfer phase** (runs in background — no app dependency):
   - OS daemon executes all uploads concurrently.
   - Delegate fires for each completed transfer; results tracked in manifest.
   - The coordinator does NOT need to be alive during this phase.

3. **Confirm phase** (brief app execution — delegate wake-up or foreground):
   - When all transfers complete, the delegate fires `urlSessionDidFinishEvents`.
   - The app calls `confirmUploadBatch` (one API call).
   - Success UI / notification.

4. **Retry on relaunch:**
   - If the app was killed and relaunched, check the manifest.
   - Completed uploads: call `confirmUploadBatch` for them.
   - Failed uploads: re-request presigned URLs for just the failed clips and re-enqueue.

### `SharedTapeDownloadCoordinator.swift`

Replace the sequential loop with:

1. **Prepare phase** (foreground):
   - Fetch manifest (already one API call).
   - Compute delta (existing clips vs server clips — unchanged).
   - Submit all download tasks at once.

2. **Transfer phase** (background):
   - OS daemon runs all downloads.
   - Delegate moves each file to a stable location; result tracked in manifest.

3. **Process phase** (delegate wake-up or foreground):
   - When all downloads complete, process results:
     - Save each file to Photos library.
     - Build Clip objects.
     - Add/merge into TapesStore.
     - Confirm downloads to server (can be batched or fire-and-forget).

4. **Retry on relaunch:**
   - Check manifest for incomplete batches.
   - Successfully downloaded files (already in stable temp location): process them.
   - Failed downloads: re-enqueue.

### `CollabSyncCoordinator.swift`

No structural changes. It composes `ShareUploadCoordinator` and `SharedTapeDownloadCoordinator`. Both now use batch submissions internally. The sync coordinator's progress aggregation continues to work because `completedClips` / `completedCount` are still incremented as delegate callbacks arrive.

### `ExportCoordinator.swift`

No changes. Export is local CPU work, not network transfers.

### Dynamic Island / `BGContinuedProcessingTask`

Same as current implementation:
- Submit the continued processing task for the Dynamic Island.
- Update progress as delegate callbacks arrive.
- On expiration: report "Continuing in background…" + success.
- The transfer is independent of the task's lifecycle.

### Preferences / cellular toggle

No changes. `allowsCellularAccess` on the background session configuration already applies to all tasks submitted to that session.

---

## File-level change summary

### Server (tapes-api)

| File | Change |
|------|--------|
| `src/routes/clips.ts` (or equivalent) | Add `prepareUploadBatch` handler — loop of existing createClip + presigned URL logic |
| `src/routes/clips.ts` (or equivalent) | Add `confirmBatch` handler — loop of existing confirmUpload logic |
| `src/index.ts` (router) | Register two new routes |

### iOS

| File | Change |
|------|--------|
| `TapesAPIClient.swift` | Add `prepareUploadBatch` and `confirmUploadBatch` methods + response structs |
| `BackgroundTransferManager.swift` | Add batch submission methods, task-to-clip mapping, batch completion tracking |
| `TransferManifest.swift` | Add `batchId`, `status`, `cloudUrl` fields; add batch query methods |
| `ShareUploadCoordinator.swift` | Replace sequential loop with prepare → batch submit → confirm |
| `SharedTapeDownloadCoordinator.swift` | Replace sequential loop with batch download submission |
| `CollabSyncCoordinator.swift` | Minor: adapt to new coordinator APIs if signatures change |

### No changes

| File | Reason |
|------|--------|
| `AppDelegate.swift` | Already has `handleEventsForBackgroundURLSession` |
| `TapesApp.swift` | Already calls `BackgroundTransferManager.shared.reconnect()` |
| `ExportCoordinator.swift` | Local CPU work, not network |
| `PreferencesView.swift` | Cellular toggle already works |
| All server endpoints except the two new ones | Backward compatible |

---

## Presigned URL expiry

Current: 1 hour.
Proposed: **2 hours** for batch-generated URLs.

A 66-clip tape with average clip size of 10 MB = ~660 MB total. On a slow cellular connection (~2 Mbps), this takes ~44 minutes. With 2-hour expiry, there is comfortable margin. On Wi-Fi, the entire transfer completes in minutes.

If a presigned URL does expire before the OS daemon starts the upload (extremely unlikely — the daemon starts tasks promptly), the upload fails with HTTP 403. The retry logic detects this, re-requests URLs for just the failed clips, and re-enqueues them.

---

## Concurrency and system limits

- `httpMaximumConnectionsPerHost = 4` on the session configuration — the system limits to 4 concurrent transfers to the same R2 host.
- Background sessions have an internal task limit, but iOS handles scheduling transparently. Queuing 200+ tasks (66 clips × 3 files each = up to 198 tasks) is well within bounds — apps like Google Photos and Dropbox routinely queue thousands.
- `isDiscretionary = false` ensures the system does not defer transfers to "optimal" times.
- `sessionSendsLaunchEvents = true` ensures the app is relaunched to receive results.

---

## Data integrity

### Uploads
- **Idempotent presigned URLs:** re-uploading to the same URL overwrites the same R2 object. Safe to retry.
- **Idempotent confirm:** re-confirming an already-confirmed clip is a no-op.
- **Partial success:** if 60 of 66 clips upload successfully, the batch confirm confirms those 60. The user can retry the remaining 6.
- **Orphan cleanup:** R2 assets without confirmed D1 records are cleaned up by the hourly cron job (existing).

### Downloads
- **Save to Photos is idempotent-ish:** re-saving the same image/video creates a duplicate in the Photos library. To avoid this, the coordinator checks existing local clips (the delta logic already handles this).
- **Confirm download is idempotent:** re-confirming is a no-op.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Presigned URLs expire before upload starts | Very low | 2-hour expiry. Retry logic re-requests for failed clips only |
| System throttles background tasks for large batches | Low | `isDiscretionary = false`. Tested by Google Photos / Dropbox at scale |
| Worker timeout on `prepare-upload` for 66+ clips | Low | Presigned URL generation is CPU-only (signing), no I/O per URL. 66 URLs takes <100ms |
| Temp files fill device storage | Low | Each clip's temp file is deleted when its upload task completes. Max concurrent disk usage = total tape size (same as current) |
| App killed between prepare and submit | Medium | Manifest stores the batch. On relaunch, check if tasks were submitted. If not, re-prepare. If yes, reconnect session |
| Network switch (Wi-Fi → cellular) during batch | None | Background URLSession handles this transparently |
| User cancels mid-batch | None | `cancelAllTasks()` cancels all queued tasks. Delegate fires with `NSURLErrorCancelled` for each |

---

## Verification steps

1. **Small tape (3 clips), Wi-Fi, foreground:** Share → verify all 3 clips uploaded → confirm succeeds.
2. **Large tape (30+ clips), Wi-Fi, background immediately:** Share → background the app immediately after "Uploading…" appears → verify Dynamic Island shows progress → verify all clips confirmed on server → notification on completion.
3. **Large tape, force-quit during transfer:** Share → background → force-quit from app switcher → wait for transfers to complete (check R2) → relaunch app → verify batch confirm is sent automatically → completion dialog.
4. **Large tape, cellular, slow connection:** Share on cellular → background → verify transfers continue → verify all clips arrive on server.
5. **Cellular toggle off, cellular only:** Toggle off → share → verify transfers are held (not failed) → connect to Wi-Fi → verify transfers start.
6. **Download, large shared tape:** Open shared tape link → background immediately → verify all clips downloaded → Photos library has all media → completion notification.
7. **Download, force-quit:** Same as #3 but for downloads.
8. **Partial failure + retry:** Simulate 5 of 30 clips failing (e.g. expired URLs) → verify the 25 successful clips are confirmed → retry → verify only the 5 failed clips are re-uploaded.
9. **Cancel mid-batch:** Start upload of 30 clips → cancel after 10 → verify all background tasks cancelled → no orphan confirms sent.
10. **Export regression:** Export → background → verify Dynamic Island does not show "Failed."

---

## Execution order

### Phase 1: Server (deploy first — additive, no breaking changes)
1. Add `POST /tapes/:id/prepare-upload` endpoint
2. Add `POST /tapes/:id/confirm-batch` endpoint
3. Deploy to live Worker
4. Verify both endpoints with curl / manual testing

### Phase 2: iOS (after server is live)
1. Add `prepareUploadBatch` / `confirmUploadBatch` to `TapesAPIClient`
2. Extend `TransferManifest` with batch tracking fields
3. Extend `BackgroundTransferManager` with batch submission + completion tracking
4. Rewrite `ShareUploadCoordinator` to use batch flow
5. Rewrite `SharedTapeDownloadCoordinator` to use batch flow
6. Verify on device

### Phase 3: Documentation
1. Update API contract (`API_CONTRACT_V1.md`)
2. Update feature doc (`BackgroundTransfers.md`)
3. Update Runbook

---

## Rollback

- **Server:** both new endpoints are additive. Removing them does not affect existing clients. Old per-clip flow continues to work.
- **iOS:** revert to the sequential loop (the old `uploadClip` method and `downloadClip` method). The `BackgroundTransferManager` infrastructure stays — only the coordinator logic changes.
- **No data migration.** No schema changes. No breaking changes to existing D1 tables.
