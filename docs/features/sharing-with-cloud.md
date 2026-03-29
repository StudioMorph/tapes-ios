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

## Related Files

- `Tapes/Core/Music/MubertAPIClient.swift` — existing API client pattern to follow.
- `Tapes/Export/ExportCoordinator.swift` — background task + progress UI pattern.
- `Tapes/Core/Auth/AuthManager.swift` — Sign in with Apple, needed for share identity.
- `Tapes/Platform/Photos/TapeAlbumServicing` — existing album association logic.

## Priority

Future feature. Not planned for MVP. Document exists to preserve the architectural discussion and cost analysis for when development begins.
