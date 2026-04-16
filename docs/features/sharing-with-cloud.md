# Share with Grandma — Cloud Sharing Feature

## Summary

Subscription-based tape sharing via Cloudflare R2 cloud storage. Users share tapes with family/friends who have the Tapes app installed. Shared tapes stream from the cloud, not from the receiver's iCloud storage.

## Concept

- **My Tapes**: Live locally on device + iCloud Photos (existing behaviour).
- **Shared with me**: Tapes live on our cloud (Cloudflare R2). Receiver's device holds references, not copies. Media streams/downloads from R2.
- Only the **first share** of a tape incurs upload cost. Subsequent views by any receiver stream from the same stored assets.
- Gated behind the "Share with Grandma" subscription tier at £/$4.99/month.

## Architecture

### Storage Layer

| Component | Service | Cost |
|---|---|---|
| Media (video/images) | Cloudflare R2 | $0.015/GB/month storage, **$0 egress** |
| Tape metadata (JSON) | Cloudflare D1 or CloudKit | Negligible / free |
| API / upload orchestration | Cloudflare Workers or Railway | Minimal |

### Flow: Sender shares a tape

1. User taps "Share Tape" on a tape card.
2. App uploads media assets to R2 (background upload with progress).
3. Tape metadata (clip order, transitions, music mood, trim points, orientation, duration settings) stored in metadata DB.
4. Share link or notification sent to receiver(s).

### Flow: Receiver loads a tape

1. Receiver gets notification: "A tape was shared with you."
2. Action: **Load Tape** / Dismiss.
3. On "Load Tape": app fetches metadata, builds the tape, streams media from R2.
4. Tape appears in a "Shared with me" section in the app.
5. Media is cached locally for offline playback but does not import into the receiver's Photos/iCloud.

### Flow: Sender updates a shared tape

- If the sender adds/removes clips or changes settings after sharing, a delta sync updates the cloud version.
- Receiver sees updates next time they open the tape (or via push notification).

## Constraints

- **Max 200 assets per tape** — caps per-tape storage cost.
- **Shared tape expiration**: 90 days unless the receiver explicitly "saves" it. Keeps storage from growing unbounded.
- **Upload compression**: Transcode videos to 720p before upload to halve storage. Originals stay on the sender's device. Full-quality sharing could be a future premium add-on.

## Cost Estimate Per User

### Assumptions

- ~10 tapes shared per month (first share only counts).
- Average tape: ~30 clips, ~330MB total.
- ~3.3GB uploaded per month per active sharing user.
- With 90-day expiration, active storage stabilises around 10–15GB per user.

### Monthly cost breakdown

| Item | Cost |
|---|---|
| Storage (avg 10–15GB on disk) | $0.15 – $0.23 |
| Upload operations | ~$0.004 |
| Egress (streaming to receivers) | **$0** |
| Metadata DB | ~$0 (free tier) |
| **Total per user/month** | **~$0.15 – $0.25** |

### Revenue vs cost at $4.99/month

| | Year 1 (Apple 30%) | Year 2+ (Apple 15%) |
|---|---|---|
| Revenue after Apple cut | $3.49 | $4.24 |
| Infrastructure cost | $0.15 – $0.25 | $0.15 – $0.25 |
| **Margin** | **~$3.25 (~93%)** | **~$4.00 (~95%)** |

Even heavy users ($0.50–0.75/month infra cost) remain profitable at 80%+ margin.

## Technical Requirements

### iOS App

- Background upload manager (chunked upload to R2 with retry/resume).
- Upload progress UI (reuse existing export progress pattern).
- "Shared with me" section in the app (separate from "My Tapes").
- Push notification support for incoming shared tapes.
- Local media cache for offline playback of shared tapes.
- `Transferable` protocol conformance for potential `.tape` file fallback (AirDrop).

### Backend

- **Cloudflare R2**: Media blob storage.
- **Cloudflare D1** (or CloudKit): Tape metadata, share records, user associations.
- **Cloudflare Workers** (or lightweight API): Upload orchestration, share link generation, notification triggers.
- **APNs**: Push notifications for "tape shared with you" alerts.

### Authentication

- Sign in with Apple provides user identity for share graph (who shared what with whom).
- This is where Sign in with Apple becomes genuinely useful — mapping share relationships between users.

## Not In Scope (v1)

- Live collaboration / real-time co-editing of tapes.
- Comments or reactions on shared tapes.
- Public/link-based sharing (only user-to-user via Apple ID).
- Same-account multi-device sync (separate feature, use CloudKit + iCloud Photos).

## Open Questions

- Should the receiver be able to "save" a shared tape to their own library (copies assets to their iCloud)?
- Should shared tapes be playback-only, or can the receiver edit/remix?
- Notification mechanism: APNs direct, or via a share link in Messages?
- How to handle the sender deleting their account — expire all shared tapes, or keep them alive for a grace period?

## Background Upload Architecture

Sharing uploads run in the background via `ShareUploadCoordinator`, mirroring the export pattern from `ExportCoordinator`. Key design decisions:

- **`ShareUploadCoordinator`** (`Tapes/Core/Networking/ShareUploadCoordinator.swift`): `@MainActor ObservableObject` owned by `TapesListView` as a `@StateObject`. Manages the full upload-then-invite lifecycle.
- **Background task support**: Uses `BGContinuedProcessingTask` (iOS 26+) for extended background time, with `UIApplication.beginBackgroundTask` as fallback for older iOS.
- **Modal dismissal**: When `ShareFlowView` initiates a share requiring clip uploads, it delegates to the coordinator and immediately dismisses. The user can navigate freely while uploads continue.
- **Progress overlay**: `ShareUploadProgressDialog` (GlassAlertCard) displays on `TapesListView` with clip progress, ETA, and cancel option. When dismissed, a small blue progress ring appears in the toolbar.
- **Completion**: On success, the coordinator sends invites, then shows a completion dialog (or local notification if backgrounded) with sound/haptic feedback.
- **Error handling**: Upload failures are surfaced via a native alert with retry/cancel options.
- **BG task identifier**: `StudioMorph.Tapes.upload` (registered in `Info.plist` and `TapesApp.init`).

## Collaborative Fork Architecture

When a tape owner shares a tape as **collaborative**, the original tape in "My Tapes" stays completely untouched — no `shareInfo` is attached. Instead, a **fork** (duplicate) is created in the "Shared > Collaborating" segment:

1. **Owner shares as collaborative** — `ShareUploadCoordinator` uploads clips and sends invites. On completion, `TapesListView` detects the success and calls `TapesStore.forkTapeForCollaboration()`.
2. **Fork creation** — A new `Tape` object is created with a fresh `UUID`, copies of all clips (marked as `isSynced`), and a `ShareInfo` linking it to the server-side `remoteTapeId`.
3. **Original stays personal** — The original tape in "My Tapes" has no `shareInfo`, so `isShared == false`. It can be edited, deleted, or shared again independently.
4. **Fork receives contributions** — When a collaborator contributes clips, the push notification triggers `SharedTapeDownloadCoordinator.startDownload()`, which detects the existing fork via `remoteTapeId` and **merges** only new clips (deduplicating by clip ID).
5. **No duplication on re-open** — If the user taps a share link for a tape they already have, `startDownload` skips clips that already exist locally.

### Data flow

```
[My Tapes]  →  Original tape (shareInfo = nil, untouched)
                    ↓ on collaborative share success
[Shared > Collaborating]  →  Forked tape (shareInfo set, syncs contributions)
```

### View-only shares

View-only shares do **not** create a fork. The original tape is uploaded and a link is generated, but the owner's tape remains unchanged. Recipients get their own independent copy via `SharedTapeDownloadCoordinator`.

## Shared Tape Media Storage

When a recipient downloads a shared tape (or receives a contribution), media is saved directly to the **Photos library** — identical to how locally-created clips are stored:

1. Media is downloaded from R2 to a temporary file.
2. The file is saved to the Photos library via `PHAssetChangeRequest`, yielding a `PHAsset.localIdentifier`.
3. The temporary file is deleted.
4. The `Clip` stores the `assetLocalId` (not a file path or cloud URL).
5. Clips are associated with a Photos album named after the tape via `TapeAlbumService`.

This means:
- **R2 can be safely cleaned up** after all recipients confirm download — no cloud URL is retained on the clip.
- **No cache eviction risk** — assets live in the Photos library, which iOS never purges.
- **Shared clips are structurally identical to local clips** — both use `assetLocalId` for media resolution.

## Clip Creative Settings

When clips are uploaded (via initial share or contribution), the following creative settings are sent alongside basic metadata:

- **motion_style** — animation effect for image clips (kenBurns, pan, zoomIn, zoomOut, drift, none).
- **image_duration_ms** — display duration for image clips (only sent for photos).
- **rotate_quarter_turns** — rotation applied to the clip (0, 1, 2, or 3 quarter turns).
- **override_scale_mode** — explicit fit/fill mode (nil uses tape default).

These settings are stored in D1 (`clips` table), included in the manifest response, and applied when recipients download and rebuild the tape. Background music and modifications to other contributors' clips are explicitly excluded from contributions.

## Related Files

- `Tapes/Core/Networking/ShareUploadCoordinator.swift` — background upload coordinator; stores `sourceTape` and `resultRemoteTapeId` for fork.
- `Tapes/Views/Share/ShareUploadOverlay.swift` — progress, completion, and error dialogs.
- `Tapes/Views/Share/ShareFlowView.swift` — share configuration UI, delegates to coordinator.
- `Tapes/Views/Share/ShareModalView.swift` — entry point for sharing; shows Contribute button on forked tapes.
- `Tapes/Views/Share/SharedTapesView.swift` — Shared tab with View Only / Collaborating segments.
- `Tapes/Views/TapesListView.swift` — observes share completion to trigger `forkTapeForCollaboration`.
- `Tapes/ViewModels/TapesStore.swift` — `forkTapeForCollaboration()` and `mergeClipsIntoSharedTape()`.
- `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift` — downloads shared tapes; merges clips into existing forks.
- `Tapes/Export/ExportCoordinator.swift` — sister pattern for background exports.
- `Tapes/Core/Auth/AuthManager.swift` — Sign in with Apple, needed for share identity.
- `Tapes/Core/Networking/TapesAPIClient.swift` — API client for all backend calls.
