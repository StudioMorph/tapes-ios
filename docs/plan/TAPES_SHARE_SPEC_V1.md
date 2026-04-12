# Tapes — Share Feature Complete Specification
## Version 1.0

---

## 1. The `.tape` File

The `.tape` file is the complete portable representation of a tape. It contains everything needed to fully reconstruct, play back, and manage a tape on any device. It is a UTF-8 encoded JSON file with a custom `.tape` extension registered with the OS so tapping it opens the Tapes app directly.

**Contains:**
```json
{
  "tapes_version": "1.0",
  "tape_id": "uuid",
  "title": "Barcelona Summer",
  "mode": "collaborative",
  "expires_at": null,
  "created_at": "2026-04-12T09:00:00Z",
  "updated_at": "2026-04-12T09:00:00Z",
  "owner_id": "user_uuid",
  "owner_name": "Jose",
  "collaborators": [
    {
      "user_id": "user_uuid",
      "email": "anna@email.com",
      "role": "collaborator",
      "status": "active"
    }
  ],
  "clips": [
    {
      "clip_id": "uuid",
      "type": "video",
      "cloud_url": "https://r2.tapes.app/clips/uuid.mp4",
      "thumbnail_url": "https://r2.tapes.app/thumbs/uuid.jpg",
      "contributor_id": "user_uuid",
      "recorded_at": "2026-04-12T09:00:00Z",
      "duration_ms": 8400,
      "trim_start_ms": 0,
      "trim_end_ms": 8400,
      "audio_level": 1.0,
      "order_index": 1
    },
    {
      "clip_id": "uuid",
      "type": "photo",
      "cloud_url": "https://r2.tapes.app/clips/uuid.jpg",
      "thumbnail_url": "https://r2.tapes.app/thumbs/uuid.jpg",
      "contributor_id": "user_uuid",
      "recorded_at": "2026-04-12T10:00:00Z",
      "duration_ms": 4000,
      "audio_level": null,
      "order_index": 2,
      "ken_burns": {
        "start_rect": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0},
        "end_rect": {"x": 0.1, "y": 0.1, "w": 0.8, "h": 0.8}
      }
    },
    {
      "clip_id": "uuid",
      "type": "live_photo",
      "cloud_url": "https://r2.tapes.app/clips/uuid.mov",
      "thumbnail_url": "https://r2.tapes.app/thumbs/uuid.jpg",
      "contributor_id": "user_uuid",
      "recorded_at": "2026-04-12T11:00:00Z",
      "duration_ms": 2800,
      "trim_start_ms": 0,
      "trim_end_ms": 2800,
      "audio_level": 0.5,
      "order_index": 3,
      "live_photo_as_video": true,
      "live_photo_sound": false
    }
  ],
  "tape_settings": {
    "default_audio_level": 1.0,
    "transition": {
      "type": "crossfade",
      "duration_ms": 1100
    },
    "background_music": {
      "type": "ai_generated",
      "mood": "dreamy",
      "url": "https://r2.tapes.app/music/uuid.mp3",
      "level": 0.3
    },
    "merge_settings": {
      "orientation": "auto",
      "background_blur": true
    }
  },
  "permissions": {
    "can_contribute": true,
    "can_export": true,
    "can_save_to_device": true,
    "can_reshare": false,
    "can_invite": false
  },
  "meta": {
    "app_version": "1.0.0",
    "platform": "ios"
  }
}
```

---

## 2. Share Modal

The share modal has three distinct sections presented as a bottom sheet.

---

### Section 1 — Share With Others

#### View Only

The recipient can:
- Play back the tape in full
- AirPlay and stream to TV
- Receive live updates when the sender adds new clips

The recipient cannot:
- Contribute clips
- Export or save to device
- Re-share the tape
- Invite others

**Auto-expire option:**
- Owner can toggle 7 day expiry on or off
- On expiry: server deletes all R2 assets, tape is silently removed from recipient's app on next sync
- See Section 5 — Cloud Housekeeping for full expiry rules

---

#### Collaborative

The recipient has full tape functionality within their app for that tape including playback, contributing clips, reordering their own clips, exporting, and saving to device.

**Contributor rules:**
- Can add clips to the tape (appended to end of timeline by default)
- Can trim, adjust audio, and set photo/live photo preferences on their own clips only
- Cannot edit or delete other contributors' clips
- Cannot invite new collaborators unless they are a paying subscriber (Plus or Together) AND have been granted co-admin rights by the tape owner — enforced server-side
- Cannot revoke anyone's access

**Admin (tape owner) controls:**
- Invite new collaborators by email or from contacts
- Revoke any individual collaborator's access at any time
- Promote a collaborator to co-admin — granting them invite rights
- Demote a co-admin back to collaborator
- Delete the tape entirely — immediately revokes all access, all R2 assets deleted, tape disappears from all devices
- Trigger a **Sync Push** — sends a push notification to all collaborators who have not yet downloaded all assets, prompting them to sync before the 7 day window expires

**When a collaborator is revoked:**
- Access removed immediately
- Their contributed clips remain in the tape — tape integrity is preserved
- Tape disappears silently from their app on next sync
- No notification sent to revoked collaborator

**When a collaborator contributes a clip:**
- Clip uploads to R2 from their device
- If offline: clip is queued locally with `recorded_at` timestamp captured at time of recording, uploads automatically when connection is restored
- Server updates master tape manifest with new clip appended at end of timeline, assigned next available `order_index`
- Server resolves ordering conflicts using `uploaded_at` as tiebreaker when multiple clips arrive simultaneously
- Server resets the 7 day housekeeping window for that clip for all participants who have not yet downloaded it
- Batched push notification sent to all active collaborators (see Section 4 — Notifications)

---

#### Inviting People

- Owner adds people by email or selects from device contacts
- If recipient has Tapes installed: push notification — *"Jose invited you to collaborate on Barcelona Summer"*
- If recipient does not have Tapes: email with personalised deep link to App Store and tape preview
- When non-user installs and signs in: server confirms identity against invite, tape builds automatically on their device
- Invited users appear in collaborator list with status `invited` until they accept

---

#### Generating a `.tape` File

- Owner taps Generate .tape File
- App assembles complete `.tape` manifest including all cloud URLs, clip settings, collaborator list, and permissions
- File is presented via iOS share sheet
- Owner distributes via WhatsApp, iMessage, AirDrop, email, or any channel
- **Recipient has Tapes installed:** taps file → app opens → server validates identity → tape builds on device
- **Recipient does not have Tapes:** taps file → App Store opens → installs → signs in → server validates → tape builds
- Server validation confirms recipient is on collaborator list or tape is view-only before granting access

---

### Section 2 — Export Tape

Already built. No changes.

---

### Section 3 — Save to Device

- Available only when tape has been fully cached locally
- Creates a named album in device Photos library using tape title
- Album creation, naming, and deletion logic already built for personal tapes — same logic applies
- Saves all clips individually to album in timeline order
- Live Photos saved as Live Photos
- Videos saved as videos
- Photos saved as photos
- Entirely local operation — no server involvement

---

## 3. Server-Side Data Model

The server maintains a master tape record — the single source of truth for every shared and collaborative tape.

---

**tapes**
```
tape_id           uuid, primary key
owner_id          uuid, foreign key → users
title             text
mode              enum (view_only, collaborative)
expires_at        timestamp, nullable
created_at        timestamp
updated_at        timestamp
is_deleted        boolean, default false
manifest_url      text (cloud URL to current .tape file on R2)
```

**collaborators**
```
tape_id           uuid, foreign key → tapes
user_id           uuid, foreign key → users
email             text
role              enum (owner, co-admin, collaborator)
status            enum (invited, active, revoked)
joined_at         timestamp, nullable
invited_by        uuid, foreign key → users
```

**clips**
```
clip_id                 uuid, primary key
tape_id                 uuid, foreign key → tapes
contributor_id          uuid, foreign key → users
cloud_url               text
thumbnail_url           text
order_index             integer
duration_ms             integer
trim_start_ms           integer, nullable
trim_end_ms             integer, nullable
audio_level             float, nullable
type                    enum (video, photo, live_photo)
ken_burns_params        jsonb, nullable
live_photo_as_video     boolean, nullable
live_photo_sound        boolean, nullable
recorded_at             timestamp
uploaded_at             timestamp
is_offline_queued       boolean, default false
is_deleted              boolean, default false
```

**clip_download_tracking**
```
clip_id           uuid, foreign key → clips
user_id           uuid, foreign key → users
tape_id           uuid, foreign key → tapes
downloaded_at     timestamp, nullable
expires_at        timestamp (uploaded_at + 7 days)
is_expired        boolean, default false
```

**notification_preferences**
```
tape_id                 uuid, foreign key → tapes
user_id                 uuid, foreign key → users
notifications_enabled   boolean, default true
badge_only              boolean, default false
batch_interval_hours    integer, default 3
```

**users**
```
user_id           uuid, primary key
email             text
tier              enum (free, plus, together)
device_token      text (for push notifications)
created_at        timestamp
```

---

## 4. Notifications

**Batched updates (default):**
- Collaborators receive a single batched push notification every 3 hours summarising all new activity — *"3 new clips added to Barcelona Summer"*
- Batching prevents notification fatigue on active tapes

**User controls per tape:**
- Turn off push notifications entirely for a specific tape
- When off: app icon receives silent badge count increment only
- Badge count reflects total unseen clip additions across all tapes

**Immediate notifications — always sent:**
- Invited to collaborate on a tape
- A tape shared with you (view only)
- Owner triggers Sync Push — *"Download Barcelona Summer before clips expire in X days"*
- A tape shared with you has been deleted (silent — tape disappears, no message)
- A view-only tape has expired (silent — tape disappears, no message)

**Sync Push — triggered manually by owner:**
- Owner taps Sync Push in tape admin controls
- Server identifies all collaborators who have not fully downloaded all assets
- Immediate push sent to those users only — *"Jose wants to make sure you have Barcelona Summer synced. Tap to download before clips expire."*
- Owner can trigger Sync Push once every 24 hours per tape

---

## 5. Cloud Housekeeping

This section defines all rules governing when assets are stored in R2, when they are deleted, and how the server manages the lifecycle of every clip. This is the mechanism that keeps storage costs viable.

---

### 5.1 The Core Rule

**All clip assets in R2 are temporary. They exist only as a transfer mechanism — not as permanent storage.**

Assets are deleted from R2 as soon as they are no longer needed. The two conditions that trigger deletion are:

1. **All recipients have downloaded the asset** — deleted immediately
2. **7 days have passed since upload** — deleted regardless of download status

There are no exceptions to these rules. This applies to all tape types — view only and collaborative.

---

### 5.2 Download Tracking

Every clip upload creates a `clip_download_tracking` record for every recipient and collaborator on that tape.

- When a recipient or collaborator fully downloads a clip their `downloaded_at` is recorded
- The server checks after every download event whether all participants have now downloaded
- If all participants have downloaded → R2 assets for that clip are deleted immediately
- `expires_at` is set to `uploaded_at + 7 days` at the time of upload
- A scheduled server job runs every hour checking for records where `expires_at` has passed and `downloaded_at` is null → those assets are deleted and `is_expired` is set to true

---

### 5.3 Immediate Deletion on Full Download

When any clip is downloaded by a participant:
1. Server marks their `clip_download_tracking` record with `downloaded_at`
2. Server checks: have ALL participants for this tape now downloaded this clip?
3. If yes → R2 asset deleted immediately, `is_deleted` set to true on clip record
4. If no → asset remains, continues tracking remaining participants

This means popular tapes shared with many recipients who all download quickly will have their assets cleaned from R2 within hours of being shared — not days.

---

### 5.4 7 Day Hard Expiry

Regardless of download status:
- Every clip asset has a hard expiry of 7 days from `uploaded_at`
- Scheduled server job runs every hour
- Any clip where `expires_at` has passed and asset still exists in R2 → asset deleted immediately
- `is_expired` set to true on all remaining `clip_download_tracking` records for that clip
- Affected recipients and collaborators who did not download in time lose access to those clips

**What the affected user sees:**
- Clips that expired before download show as unavailable in the tape timeline
- A message appears in the tape — *"Some clips in this tape are no longer available"*
- The tape is not deleted — only the missing assets are gone

---

### 5.5 Collaborative Tapes — Same Rules, One Addition

Collaborative tapes follow identical housekeeping rules — 7 days, delete on full download. There are no extended windows for collaborative tapes.

**The addition — Sync Push:**
- When a clip is within 48 hours of its 7 day expiry and one or more collaborators have not downloaded it, the server automatically notifies the tape owner
- Owner sees a warning in the tape admin — *"Some collaborators haven't synced. Clips expire in 2 days."*
- Owner can trigger a Sync Push to nudge those collaborators (maximum once every 24 hours)
- If collaborators still do not download — assets expire and are deleted as normal

---

### 5.6 Tape Deleted by Owner

When owner deletes a tape:
- All clip assets in R2 are deleted immediately regardless of download status or expiry date
- All `clip_download_tracking` records marked `is_expired: true`
- Master tape record marked `is_deleted: true`
- Tape disappears silently from all collaborator and recipient devices on next sync
- No notification sent to participants

---

### 5.7 Collaborator Revoked

When a collaborator is revoked:
- Their `clip_download_tracking` records are marked `is_expired: true` immediately
- They lose access to any assets they have not yet downloaded
- Assets already downloaded to their device remain — the app cannot reach into someone's device and delete local files
- Their contributed clips remain in the tape — tape integrity is preserved
- The housekeeping job no longer waits for them to download before deleting assets — they are removed from the participant count

---

### 5.8 Orphaned Asset Cleanup

Orphaned assets are clips that were uploaded to R2 but never successfully attached to a tape record — caused by failed uploads, app crashes mid-share, or network interruptions.

- Scheduled server job runs daily
- Identifies any R2 assets older than 24 hours with no corresponding clip record in the database
- Deletes those assets immediately
- Logs deletion for debugging

---

### 5.9 Scheduled Server Jobs Summary

| Job | Frequency | What it does |
|-----|-----------|-------------|
| Expiry check | Every hour | Deletes R2 assets where `expires_at` has passed |
| Full download check | On every download event | Deletes R2 assets where all participants have downloaded |
| Sync push warning | Every hour | Notifies owner when clips within 48hrs of expiry have unsynced collaborators |
| Orphaned asset cleanup | Daily | Deletes R2 assets with no corresponding database record |
| Expired tape cleanup | Daily | Marks view-only tapes as expired, removes from recipient apps |

---

## 6. Edge Cases and Rules

**Conflict resolution:**
Two collaborators add a clip at the same moment. Server uses insertion order (the order clips are added to the tape) as source of truth for `order_index`, not `recorded_at`. `recorded_at` is metadata only — it records when the media was originally captured but has no bearing on clip position. When two clips arrive simultaneously, the server assigns `order_index` based on `uploaded_at` timestamp (first to arrive gets the earlier position) and propagates to all devices.

**Offline contributions:**
Clip recorded offline. Stored in local queue with `recorded_at` captured at time of recording. Uploads automatically on reconnection. Server appends clip at the end of the timeline (insertion order) and assigns the next available `order_index`. Server creates `clip_download_tracking` records for all participants. 7 day window starts from `uploaded_at` not `recorded_at`.

**Invite to non-user who never installs:**
Invite remains in `invited` status indefinitely. No R2 assets uploaded until tape is actually accessed. Owner can revoke invite at any time. No storage cost for uninvited users.

**Collaborative invite permissions:**
Only paying subscribers (Plus or Together) with co-admin role can invite new collaborators. Free tier collaborators cannot invite others. Enforced server-side — not just in UI. Any attempt to invite from a free account is rejected by the API.

**View only recipient re-shares:**
Not possible. Permissions field in `.tape` file sets `can_reshare: false`. App enforces this. Server also validates — any attempt to generate a new share from a view-only tape is rejected.

**Large tapes on slow connections:**
Tape building progress shown to recipient during download. Clips stream and become playable as they download — recipient does not wait for full tape to download before playback begins. Download resumes automatically if interrupted.

**Push notification delivery failure:**
If push notification fails to deliver, server falls back to email notification for the same event. Delivery failure logged for debugging.

---

## 7. Implementation Phases

---

### Phase 1 — Foundation
*Nothing else works without this*

- Set up Supabase — full database schema as defined in Section 3
- Set up Cloudflare R2 — storage bucket, access keys, CORS policy
- Build upload pipeline — clips upload from iOS to R2, server returns cloud URL per clip
- Build master tape record creation — triggered when owner initiates a share
- Build `.tape` manifest generator — assembles complete JSON from tape record and clip array as defined in Section 1
- Build `clip_download_tracking` record creation — one record per participant per clip on every upload
- Build deep link handler — `tapes://t/{shareId}` routes correctly inside app
- Build App Store fallback — deep link routes to App Store if app not installed, resumes after install and sign in

**Milestone:** A tape can be uploaded, a master record created server-side, download tracking records created, and a `.tape` file generated with all cloud URLs and settings

---

### Phase 2 — View Only Share
*First shareable product — soft launch moment*

- Build share modal UI — three sections as defined in Section 2
- Build view only share flow — set mode, optional 7 day expiry, generate share link
- Build invite flow — email input, contacts picker, push vs email routing
- Build recipient download flow — tap notification or link → app opens → server validates → tape builds on device with streaming playback as clips download
- Build full download detection — server checks after each download event, deletes R2 assets immediately when all recipients have downloaded
- Build 7 day expiry job — hourly scheduled job, R2 assets deleted on expiry, tape silently removed from recipient app on next sync
- Build push notification — *"Jose shared a tape with you"*
- Build email invite — personalised deep link, tape preview, App Store link for non-users

**Milestone:** A view-only tape can be shared via WhatsApp, iMessage, or email, fully rebuilds on recipient's device with streaming playback, and all R2 assets are cleaned up immediately on full download or after 7 days

---

### Phase 3 — Collaborative Tapes
*The killer feature*

- Build collaborative mode selection in share modal
- Build collaborator management UI — invite, role assignment, revoke, promote to co-admin, demote
- Build contribution upload flow — collaborator adds clip → uploads to R2 → server updates manifest → creates download tracking records for all participants → propagates to all participants
- Build conflict resolution — server-side timestamp ordering, final `order_index` assignment
- Build real-time sync — all participants receive updated manifest when new clip added
- Build offline contribution queue — local queue with `recorded_at` timestamp, auto-upload on reconnection, server inserts in correct position
- Build admin controls UI — revoke access, delete tape, promote co-admin, demote co-admin, trigger Sync Push
- Build permission enforcement server-side — invite rights locked to paying subscribers with co-admin role, all role-based actions validated at API level
- Build tape deletion flow — immediate R2 cleanup for all assets, access revocation across all devices
- Build access revocation flow — participant removed from download tracking, assets no longer wait for them, tape disappears silently on next sync

**Milestone:** Multiple people on different devices in different locations can contribute to one tape in real time, with server managing ordering, permissions, sync, and download tracking

---

### Phase 4 — Cloud Housekeeping Jobs
*The economics engine*

- Build hourly expiry check job — identifies clips where `expires_at` has passed, deletes R2 assets, marks tracking records as expired
- Build full download detection — runs on every download event, deletes R2 assets immediately when all participants have downloaded
- Build 48 hour sync warning job — hourly check, identifies clips nearing expiry with unsynced collaborators, notifies tape owner
- Build Sync Push — owner triggers manual push to unsynced collaborators, maximum once per 24 hours per tape, server identifies only unsynced participants
- Build daily orphaned asset cleanup — identifies R2 assets with no database record older than 24 hours, deletes immediately
- Build daily expired tape cleanup — marks expired view-only tapes, removes from recipient apps on next sync
- Build owner warning UI — tape admin shows warning when clips are within 48 hours of expiry with unsynced collaborators

**Milestone:** All R2 assets are cleaned up automatically on full download or 7 day expiry, server storage costs remain flat regardless of user growth, owners can nudge unsynced collaborators before expiry

---

### Phase 5 — Notifications
*Keeps collaborators engaged without fatigue*

- Build batched notification job — collects activity per tape per user, fires every 3 hours
- Build per-tape notification preferences UI — on/off toggle, badge-only option
- Build badge count logic — silent increment when notifications off
- Build immediate notification triggers — invite received, tape shared, Sync Push, tape deleted
- Build push delivery failure fallback — falls back to email on push failure
- Build notification preference storage — server-side per tape per user as defined in data model

**Milestone:** Collaborators stay informed without notification fatigue, full user control per tape, reliable delivery with email fallback

---

### Phase 6 — `.tape` File Distribution
*The viral acquisition mechanic*

- Build `.tape` file generator — complete manifest as defined in Section 1 including collaborator list, permissions, all clip and tape settings
- Build iOS file type registration — `.tape` extension registered in Info.plist, MIME type `application/x-tapes`, OS routes to Tapes app
- Build Android manifest registration — intent filter for `.tape` MIME type and file extension
- Build server validation on file open — confirms user identity, checks permissions, initiates tape build and download tracking
- Build non-user flow — file tap → App Store → install → sign in → server validates → tape builds automatically with streaming playback

**Milestone:** A `.tape` file shared via WhatsApp pulls a new user into the app, their tape builds automatically after sign in, and download tracking begins immediately

---

### Phase 7 — Save to Device
*Simple — mostly already built*

- Build Save to Device option in share modal — visible only when tape is fully cached locally
- Reuse existing album creation and naming logic from local tape flow
- Save all clips to named album in correct timeline order
- Handle mixed media correctly — Live Photos as Live Photos, videos as videos, photos as photos
- No server involvement — entirely local operation

**Milestone:** User can save any fully cached tape as individual clips to a named Photos album

---

### Phase 8 — Polish and Edge Cases
*Production readiness*

- All error states — upload failed, connection lost mid-upload, invite bounced, server timeout, clip expired before download
- All loading states — tape building progress indicator for recipient, upload progress per clip, sync status per collaborator in admin view
- Retry logic — failed uploads auto-retry with exponential backoff, maximum 3 attempts before user is notified
- Graceful degradation — app works fully for personal tapes if server is unreachable
- Large tape handling — streaming playback begins before full download completes
- Notification delivery confirmation — fallback to email if push fails
- Expired clip UI — clear visual indicator in timeline when clips are unavailable due to expiry
- Full test suite for permission enforcement — server-side validation of all role-based actions at API level
- Full test suite for housekeeping jobs — verify assets deleted correctly on full download and on 7 day expiry
- Performance testing — simulate 1,000 simultaneous collaborative tape contributions

---

## 8. Pricing Tiers

| Feature | Free | Plus £4.99 | Together £8.99 |
|---------|------|-----------|-------------|
| Personal tapes | 3 active | Unlimited | Unlimited |
| Shared tapes (view only) | 1 active | 20/month | 50/month |
| Collaborative tapes | ❌ | 20/month | 50/month |
| Invite collaborators | ❌ | ✅ | ✅ |
| Promote co-admin | ❌ | ✅ | ✅ |
| Receive & contribute to collaborative tapes | ✅ | ✅ | ✅ |
| View shared tapes | ✅ | ✅ | ✅ |
| Export | Watermark | No watermark | No watermark |
| Music library (12k tracks) | ❌ | ✅ | ✅ |
| AI mood-based music | ❌ | ❌ | ✅ |
| AI prompt-based music | ❌ | ❌ | ✅ |
| View only tape expiry control | ❌ | ✅ | ✅ |
| Admin controls (revoke, delete, promote) | ❌ | ✅ | ✅ |
| Generate .tape file | ❌ | ✅ | ✅ |
| Save tape to device | ✅ | ✅ | ✅ |
| Monthly | — | £4.99 | £8.99 |
| Annual (save 30%) | — | £41.99/yr | £75.99/yr |

---

## 9. What This Delivers

When all phases are complete a user can:

1. Record a tape over days, weeks, or months entirely on device at zero server cost
2. Share it instantly via WhatsApp, iMessage, or email as a link or `.tape` file
3. Recipients watch it on their device with streaming playback — no waiting for full download
4. Server assets are deleted automatically the moment everyone has downloaded — storage costs stay minimal
5. Any assets not downloaded within 7 days are hard deleted — no accumulating storage debt
6. Invite family and friends to contribute their own clips in real time to a collaborative tape
7. The tape grows across multiple devices, server manages ordering, permissions, and sync
8. Owner can nudge unsynced collaborators with a Sync Push before assets expire
9. Everyone stays informed with batched notifications — no fatigue
10. Owner has full control — revoke, delete, promote, monitor sync status
11. The `.tape` file pulls new users into the app organically — every share is a potential acquisition
12. All clip assets live in R2 only as long as needed — the server is a transfer pipe not a storage solution

This is the complete sharing engine. The economics are viable at any scale. Everything else in the product already works.
