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

## Share Model — Four Independent Links

Every tape has **four distinct share links**, one per cell in the `role × protection` matrix:

| | Unprotected (open) | Protected (email) |
|---|---|---|
| **View-only** | `view_open` | `view_protected` |
| **Collaborative** | `collab_open` | `collab_protected` |

All four share IDs are minted on tape creation (`tapes.ts → createTape`) and back-filled by `ensureAllShareIds` when an older tape is first accessed. The `collaborators` table carries a `share_variant` column and a composite unique index `(tape_id, LOWER(email), COALESCE(share_variant, '_owner'))`, so the same email can be invited to distinct variants independently.

### Why four links instead of "toggle access mode"

Each variant is a different audience:

- Users invited to the **collab-protected** link should never silently gain access if the owner flips Secured off.
- An **open collab** link handed out on social should not start letting random people in just because someone toggled "Secured by email" on later.

Treating each cell as its own audience — with its own URL and its own invite list — makes the mental model predictable and the server-side authorisation straightforward.

### Resolution

`share.ts → resolveShare` looks up the share ID across all four columns, computes `(accessMode, shareVariant, isProtected)` from the winning column, then:

- **Open variants** (`view_open`, `collab_open`): auto-join the caller with `access_mode` derived from the variant.
- **Protected variants** (`view_protected`, `collab_protected`): require the caller's email to appear in `collaborators` for that tape **and** that variant. Invited rows are flipped to `active` on first open.

The resolution payload now includes `access_mode`, `share_variant`, and `is_protected` so the iOS client can route the recipient to the correct Shared tab regardless of the tape's overall mode.

### Invite / revoke scoping

- `POST /tapes/:id/collaborators` requires `share_variant` in the body and rejects `*_open` variants (those are auto-join).
- `DELETE /tapes/:id/collaborators/:email?share_variant=…` scopes the revoke to a single variant. A user revoked from `collab_protected` can still keep access they were granted via `view_protected`, and vice versa.
- Revoking only expires previously-issued clip download URLs if the user has no other active variant on the tape — matching the principle that we cannot pull back a tape already rebuilt on another device.

## Background Upload Architecture

Sharing uploads run in the background via `ShareUploadCoordinator`, mirroring the export pattern from `ExportCoordinator`. Key design decisions:

- **`ShareUploadCoordinator`** (`Tapes/Core/Networking/ShareUploadCoordinator.swift`): `@MainActor ObservableObject` owned by `TapesListView` as a `@StateObject`. Manages the upload lifecycle and exposes a cached `CreateTapeResponse` (with all four share IDs) so the share UI can render links immediately.
- **Idempotent `ensureTapeUploaded`**: Safe to call from any share-UI entry point. If the tape has already been uploaded (`clipsUploaded == true` in the cached response), it returns without work. The first invite tap or the first **Share link** copy/share action is what triggers the upload — not a separate "Send invites" button.
- **Background task support**: Uses `BGContinuedProcessingTask` (iOS 26+) for extended background time, with `UIApplication.beginBackgroundTask` as fallback for older iOS.
- **Modal dismissal**: When an upload starts from inside `ShareModalView`, the modal dismisses itself on `uploadCoordinator.isUploading` so the global progress overlay is visible.
- **Progress overlay**: `ShareUploadProgressDialog` (GlassAlertCard) displays on `TapesListView` with clip progress, ETA, and cancel option. When dismissed, a small blue progress ring appears in the toolbar.
- **Completion**: Upload completes and the share link becomes available in the modal.
- **Error handling**: Upload failures are surfaced via a native alert with retry/cancel options.
- **BG task identifier**: `StudioMorph.Tapes.upload` (registered in `Info.plist` and `TapesApp.init`).

## Collaborative Tape Architecture

Collaborative tapes are created natively in the **Collab tab** (marked `isCollabTape = true`). There is no forking or duplication — the original tape is the collaborative tape.

1. **Created in Collab tab** — The Collab tab always has an empty tape at the top (like My Tapes). Users create content here, and these tapes can only be shared as collaborative.
2. **Direct upload** — When the owner shares, `ensureTapeUploaded` uses the tape's own UUID as the server `tape_id`. No copy is made.
3. **ShareInfo persisted after first share** — `ShareLinkSection.finaliseShareInfo()` calls `TapesStore.setCollabShareInfo()` to store the server-provided `shareId` and `remoteTapeId` on the tape.
4. **Tape receives contributions directly** — Contributors' clips land on the same tape. The owner sees contributions merged in.
5. **No duplication on re-open** — If a user taps a share link for a tape they already have, `startDownload` skips clips that already exist locally.
6. **Owner blocked from re-downloading** — If `resolveShare` returns `userRole == "owner"`, the download is aborted and a dialog is shown: "This is your tape. It already exists on your device."
7. **Received tapes are never `isCollabTape`** — Downloaded collaborative tapes keep `isCollabTape = false`. Their collaborative nature is identified via `shareInfo.mode == "collaborative"`. This ensures the share modal only shows the contribute button (no share section) for contributors.

### Data flow

```
[Collab tab]  →  Owner's collab tape (isCollabTape = true, uploaded under its own UUID)
                    ↓ shared via link
[Collab tab on receiver's device]  →  Received collab tape (isCollabTape = false, identified by shareInfo.mode)
```

### My Tapes (view-only only)

Tapes in My Tapes can **only** be shared as view-only. The share section has no segmented control — it is always view-only. The original tape is uploaded under its own UUID and a link is generated. Recipients get their own independent copy via `SharedTapeDownloadCoordinator` in the **Shared** tab.

## Shared Tape Media Storage

When a recipient downloads a shared tape (or receives a contribution), media is saved directly to the **Photos library** — identical to how locally-created clips are stored:

1. Media is downloaded from R2 to a temporary file.
2. The file is saved to the Photos library via `PHAssetChangeRequest`, yielding a `PHAsset.localIdentifier`.
3. The temporary file is deleted.
4. The `Clip` stores the `assetLocalId` (not a file path or cloud URL).
5. Clips are associated with a Photos album named after the tape via `TapeAlbumService`.

This means:
- **R2 assets are retained for 3 days** from the last share action, then purged by a daily scheduled job — no cloud URL is retained on the clip after cleanup.
- **No cache eviction risk** — assets live in the Photos library, which iOS never purges.
- **Shared clips are structurally identical to local clips** — both use `assetLocalId` for media resolution.

## Clip Creative Settings

When clips are uploaded (via initial share or contribution), the following creative settings are sent alongside basic metadata:

- **motion_style** — animation effect for image clips (kenBurns, pan, zoomIn, zoomOut, drift, none).
- **image_duration_ms** — display duration for image clips (only sent for photos).
- **rotate_quarter_turns** — rotation applied to the clip (0, 1, 2, or 3 quarter turns).
- **override_scale_mode** — explicit fit/fill mode (nil uses tape default).

These settings are stored in D1 (`clips` table), included in the manifest response, and applied when recipients download and rebuild the tape. Background music and modifications to other contributors' clips are explicitly excluded from contributions.

## Live Photo Sharing

Live Photos are shared with full fidelity — both the still image and the paired video component are preserved.

### Upload path

1. `ShareUploadCoordinator.uploadClip` detects `clip.isLivePhoto` and sends `type: "live_photo"` (with `live_photo_as_video` and `live_photo_sound` settings) to `POST /tapes/:id/clips`.
2. The backend returns a third presigned URL (`live_photo_movie_upload_url`) alongside the standard media and thumbnail URLs.
3. The still image (JPEG) is uploaded to the primary `upload_url`; the paired video (.mov) is extracted via `PHAssetResourceManager` (`.pairedVideo` resource type) and uploaded to the movie URL.
4. `confirmUpload` sends the base URLs for all three objects (cloud, thumbnail, movie) so the backend stores `live_photo_movie_url` in the `clips` table.

### Download path

1. The manifest includes `live_photo_movie_url` (signed) for `live_photo` clips.
2. `SharedTapeDownloadCoordinator` downloads both the still image and the movie to temp files.
3. The clip is saved to the Photos library as a proper Live Photo using `PHAssetCreationRequest` with `.photo` (data) and `.pairedVideo` (fileURL) resources — the same approach used by the custom camera.
4. The resulting `Clip` has `isLivePhoto = true`, `livePhotoAsVideo`, and `livePhotoMuted` set from the manifest, ensuring playback behaviour matches the sender's settings.

### Backend

- D1 `clips` table has a `live_photo_movie_url` column (migration `0008_live_photo_movie_url.sql`).
- The `createClip` endpoint generates presigned upload URLs for both the still and movie when `type == 'live_photo'`.
- The manifest endpoint signs and returns `live_photo_movie_url` alongside `cloud_url`.
- Cleanup is handled by the tape-level R2 retention policy (see below), not by `confirmDownload`.

## R2 Asset Retention Policy

Shared assets are kept in R2 for **3 days** from the last share or re-share action, managed at the tape level.

### How it works

1. **On every share action** — `createTape` (for existing tapes) and `confirmUpload` set `tapes.shared_assets_expire_at` based on the tape mode: **3 days** for view-only tapes, **7 days** for collaborative tapes. For collaborative tapes, contributions also reset the timer (giving participants more time to sync).
2. **`confirmDownload` tracks but does not delete** — When a recipient confirms a clip download, the tracking record is updated (`downloaded_at` timestamp) but no R2 objects are removed and no clips are soft-deleted.
3. **Daily scheduled cleanup** (`runSharedAssetCleanup`, runs at 04:00 UTC) — Finds tapes where `shared_assets_expire_at < now`, deletes all R2 objects (media, thumbnails, Live Photo movies) for those tapes, soft-deletes the clip records, expires download tracking, and clears `shared_assets_expire_at`.
4. **Re-sharing after expiry** — If a tape's assets have been purged and the owner shares again, `ensureTapeUploaded` (delta sync) detects no clips on the server and performs a full re-upload.

### D1 schema

- `tapes.shared_assets_expire_at TEXT` — ISO 8601 timestamp; `NULL` means no shared assets are live (migration `0009_shared_assets_expire_at.sql`).

## Sync Badge

A reusable `SyncBadge` component (in `DesignSystem/SyncBadge.swift`) shows a blue count circle and an animated directional arrow on tape cards.

### Where it appears

| Location | Direction | Condition |
|---|---|---|
| **Shared / Collaborating** tapes | Arrow DOWN | Server manifest has clips the local tape does not (`TapeSyncChecker` compares on appear) |
| **My Tapes** (view-only, previously shared) | Arrow UP | `tape.pendingUploadCount > 0` (local non-placeholder clips exceed `lastUploadedClipCount`) |

### Data flow

1. **Download badge** — `TapeSyncChecker` fetches server manifests for collaborative tapes on `SharedTapesView.onAppear` (5-minute cooldown). Publishes `pendingDownloads[tapeId]`. Tapping the badge triggers a re-download via the existing `SharedTapeDownloadCoordinator`.
2. **Upload badge** — After a successful share, `ShareUploadCoordinator` sets `lastUploadedClipCount`. `TapesListView` observes this and calls `tapesStore.setLastUploadedClipCount()`. `Tape.pendingUploadCount` is a computed property comparing local clips to the stored count. Tapping the badge opens the share modal.

## Related Files

- `Tapes/Core/Networking/ShareUploadCoordinator.swift` — background upload coordinator; stores `sourceTape` and exposes `resultCreateResponse` (all four share IDs).
- `Tapes/Views/Share/ShareUploadOverlay.swift` — progress, completion, and error dialogs.
- `Tapes/Views/Share/ShareLinkSection.swift` — inline sharing UI embedded in `ShareModalView`: `Secured by email` toggle, link pill (copy + system share sheet), email compose, authorised-users chips. Role is determined by `tape.isCollabTape`.
- `Tapes/Views/Share/ShareModalView.swift` — entry point for sharing; embeds `ShareLinkSection` directly, shows Contribute button for non-owner collaborative tapes.
- `Tapes/Views/Share/SharedTapesView.swift` — Shared tab (view-only tapes only).
- `Tapes/Views/Share/CollabTapesView.swift` — Collab tab with empty-tape creation and owner/contributor sections.
- `Tapes/Views/TapesListView.swift` — My Tapes list with upload badge and sync upload trigger.
- `Tapes/ViewModels/TapesStore.swift` — `setCollabShareInfo()`, `collabTapes`, and empty collab tape management.
- `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift` — downloads shared tapes; blocks owners from re-downloading their own tape (`userRole == "owner"` check).
- `Tapes/Export/ExportCoordinator.swift` — sister pattern for background exports.
- `Tapes/Core/Auth/AuthManager.swift` — Sign in with Apple, needed for share identity.
- `Tapes/Core/Networking/TapesAPIClient.swift` — API client for all backend calls.
- `Tapes/Core/Networking/TapeSyncChecker.swift` — lightweight manifest checker for download badges.
- `Tapes/DesignSystem/SyncBadge.swift` — reusable sync badge component (count + animated arrow).
