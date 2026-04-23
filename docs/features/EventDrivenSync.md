# Event-Driven Sync Architecture

## Summary

Server-authoritative sync system using APNs push notifications and a lightweight status endpoint, replacing per-tape manifest polling.

## Purpose & Scope

Eliminates the O(N) manifest polling loop that fired every 60 seconds, fetching full manifests for every shared/collaborative tape just to compute badge counts. Replaced with a three-layer event-driven architecture that uses one API call regardless of tape count.

## Architecture

### Layer 1 — Push Notifications (real-time, batched)

Before uploading clips, the iOS client declares an upload batch via `POST /tapes/:id/upload-batch` with the expected clip count, batch type (`invite` or `update`), and mode (`view_only` or `collaborative`). Each `POST /clips/:id/uploaded` increments a server-side counter. When the counter reaches the expected count, the server sends **one** consolidated APNs push to all other participants. iOS receives this in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and triggers an immediate sync status check.

Push payload (update example):
```json
{
  "aps": {
    "alert": { "title": "Tape Update - Barcelona", "body": "Jose added 5 new clips to this tape" },
    "sound": "default",
    "badge": 1,
    "content-available": 1,
    "category": "TAPE_SHARE"
  },
  "tape_id": "uuid",
  "share_id": "short_id",
  "action": "sync_update",
  "clip_count": 5
}
```

Push payload (invite example):
```json
{
  "aps": {
    "alert": { "title": "Tape invite", "body": "Jose invited you to see and follow their \"Barcelona\" Tape" },
    "sound": "default",
    "badge": 1,
    "content-available": 1,
    "category": "TAPE_INVITE"
  },
  "tape_id": "uuid",
  "share_id": "short_id",
  "action": "tape_invite",
  "tape_title": "Barcelona",
  "owner_name": "Jose",
  "mode": "view_only"
}
```

### Layer 2 — Lightweight Status Check (fallback)

`POST /sync/status` accepts an optional array of tape IDs and returns pending download counts from the authoritative `clip_download_tracking` table. One request, one D1 query, tiny response.

Request:
```json
{ "tape_ids": ["uuid1", "uuid2", ...] }
```

Response:
```json
{ "tapes": { "uuid1": 3, "uuid2": 1 } }
```

Only tapes with pending downloads are returned. Runs every 5 minutes as a safety net for missed pushes.

### Layer 3 — Full Manifest (download-only)

`GET /tapes/:id/manifest` remains unchanged but is only called when the user initiates a download. Never used for badge computation.

## Key UI Components

No UI changes. All views (`SharedTapesView`, `CollabTapesView`, `TapesList`) continue reading from `TapeSyncChecker.pendingDownloads`. The data source changed; the consumer did not.

## Data Flow

```
Device A declares upload batch
  → POST /tapes/:id/upload-batch (clip_count=5, batch_type, mode)
  → Worker creates batch record (expected_count=5, completed_count=0)

For each clip on device A:
  → POST /clips/:id/uploaded (Worker)
  → Worker creates tracking records + increments batch counter
  → When completed_count == expected_count:
    → Worker sends ONE consolidated APNs push to all participants
    → Device B receives push in background
    → AppDelegate → PushNotificationManager.handleBackgroundPush
    → TapeSyncChecker.updateFromPush (instant badge bump)
    → TapeSyncChecker.refresh → POST /sync/status (authoritative count)
    → pendingDownloads updated → SwiftUI badges react

Every 5 minutes (fallback):
  → Timer fires in MainTabView
  → TapeSyncChecker.checkAll → POST /sync/status
  → pendingDownloads updated
```

## Server Changes (tapes-api)

- `src/routes/sync.ts` — added `syncStatus()` handler for `POST /sync/status`
- `src/lib/apns.ts` — added `content-available: 1` and `action: "sync_update"` to all push payloads; updated to construct batch-aware notification text based on `batch_type` and `mode`
- `src/routes/clips.ts` — fixed `confirmDownload` response to include `asset_deleted` field; `confirmUpload` now increments batch counter and only sends push when batch completes
- `src/routes/batches.ts` — new: handles `POST /tapes/:id/upload-batch` to declare upload batches
- `src/index.ts` — registered `POST /sync/status` route

## iOS Changes (tapes-ios)

- `TapeSyncChecker.swift` — rewritten: uses `POST /sync/status` instead of per-tape manifest fetching; added `updateFromPush()` for instant push-driven updates; interval changed from 60s to 300s
- `TapesAPIClient.swift` — added `syncStatus(tapeIds:)` and `declareUploadBatch(tapeId:clipCount:batchType:mode:)` methods; removed `syncPush(tapeId:)`; made `DownloadConfirmResponse.assetDeleted` optional
- `AppDelegate.swift` — added `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` for silent/background push handling
- `PushNotificationManager.swift` — added `syncChecker`, `tapesProvider` properties; added `handleBackgroundPush()` method; `willPresent` now also triggers sync on `sync_update` action
- `MainTabView.swift` — wires `syncChecker` and `tapesProvider` into `PushNotificationManager` on `.task`

## Testing / QA Considerations

- Push notifications require a physical device (not simulator)
- Silent pushes are throttled by iOS — the 5-minute fallback timer ensures badges update even when pushes are delayed
- Verify badge counts match between push-driven and status-driven updates
- Test app in background, force-quit, and Low Power Mode scenarios
- Server must be deployed with `wrangler deploy` for the new `/sync/status` endpoint to be available

## Related

- API Contract: `docs/plan/API_CONTRACT_V1.md`
- Sharing Foundation: `docs/features/SharingFoundation.md`
- Runbook: `RUNBOOK.md` §8 (Sync Architecture)
