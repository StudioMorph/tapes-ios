# Sharing Feature — Build Roadmap

Reference: `docs/plan/TAPES_SHARE_SPEC_V1.md`

---

## Overview

The work splits into two tracks that run in parallel where possible:
- **Backend** — Cloudflare Workers API + D1 database + R2 storage (new repo: `tapes-api`)
- **iOS** — New views, networking layer, local caching, deep links (existing repo: `tapes-ios`)

Single `feature/sharing` branch, merged to `main` at meaningful milestones.

---

## Phase 1 — Foundation ✅

### Backend (tapes-api)
1. Scaffold Cloudflare Workers project with Wrangler
2. Create R2 bucket (`tapes-media`) with CORS policy
3. Create D1 database (`tapes-db`) with full schema: `users`, `tapes`, `collaborators`, `clips`, `clip_download_tracking`, `notification_preferences`
4. Build API endpoints:
   - `POST /tapes` — create master tape record
   - `POST /tapes/:id/clips` — generate presigned R2 upload URL, create clip record
   - `GET /tapes/:id/manifest` — return complete `.tape` JSON
   - `POST /tapes/:id/clips/:clipId/downloaded` — mark clip downloaded for user, trigger full-download check
5. Wire up download tracking — on every upload, create tracking records for all participants
6. Deploy to Cloudflare (dev environment)

### iOS (tapes-ios)
1. Build `TapesAPIClient` — networking layer to talk to Workers API (auth headers, JSON encoding/decoding)
2. Build `CloudUploadManager` — background upload pipeline (chunked upload to R2 presigned URLs with retry/resume, progress reporting)
3. Build `.tape` file model — `Codable` struct matching the spec JSON schema
4. Build `.tape` manifest generator — serialise local tape into `.tape` JSON with cloud URLs
5. Register `tapes://t/{shareId}` deep link in Info.plist + `SceneDelegate`/`onOpenURL` handler
6. Register `.tape` file type in Info.plist (`application/x-tapes`, UTI)

**Milestone:** A tape can be uploaded to R2, a server record created, and a `.tape` file generated. Deep links route into the app.

---

## Phase 2 — View Only Share

### Backend
1. `POST /tapes/:id/share` — create view-only share, set expiry, generate share link
2. `POST /tapes/:id/invite` — invite by email, create collaborator record with status `invited`
3. `GET /tapes/:id/validate` — validate recipient identity + permissions on tape open
4. Build APNs integration — send push on share ("Jose shared a tape with you")
5. Build email invite sender — personalised deep link + tape preview for non-users
6. Housekeeping: 7-day expiry cron job (Workers Cron Trigger, hourly)
7. Housekeeping: full-download detection → immediate R2 delete

### iOS
1. Build Share Modal UI — bottom sheet with three sections (Share, Export, Save to Device)
2. Build view-only share flow — mode selection, expiry toggle, invite contacts
3. Build contacts/email picker for inviting recipients
4. Build recipient download flow — tap notification/link → validate → stream + cache tape
5. Build "Shared with me" section in tape list
6. Build streaming playback — clips become playable as they download, progress indicator
7. Push notification handling — tap opens tape

**Milestone:** View-only sharing works end to end. Assets auto-clean from R2.

---

## Phase 3 — Collaborative Tapes

### Backend
1. `POST /tapes/:id/collaborate` — create collaborative share
2. `POST /tapes/:id/clips` (contributor) — upload clip, update manifest, create tracking records, resolve ordering
3. `PUT /tapes/:id/collaborators/:userId/role` — promote/demote co-admin
4. `DELETE /tapes/:id/collaborators/:userId` — revoke access, remove from tracking
5. `DELETE /tapes/:id` — delete tape, purge all R2 assets, revoke all access
6. Permission enforcement — all role-based actions validated server-side against user tier + role

### iOS
1. Build collaborative mode in share modal
2. Build collaborator management UI — invite, roles, revoke, promote/demote
3. Build contribution upload flow — add clip → upload → manifest updates for all participants
4. Build offline contribution queue — local queue with `recorded_at`, auto-upload on reconnection
5. Build admin controls UI — revoke, delete tape, promote co-admin, Sync Push trigger
6. Build sync — pull updated manifest when push received, download new clips

**Milestone:** Multiple people contribute to one tape from different devices.

---

## Phase 4 — Cloud Housekeeping

### Backend (all backend)
1. Hourly expiry cron — delete R2 assets past 7 days
2. Full download detection — delete immediately when all participants synced (built in Phase 2, hardened here)
3. 48-hour warning cron — notify owner when clips near expiry with unsynced collaborators
4. Sync Push endpoint — `POST /tapes/:id/sync-push` (max once per 24h)
5. Daily orphan cleanup — R2 assets with no DB record older than 24h
6. Daily expired tape cleanup — mark view-only tapes expired, flag for removal

### iOS
1. Owner warning UI — badge/indicator when clips nearing expiry with unsynced collaborators
2. Sync Push button in admin controls
3. Expired clip UI — visual indicator in timeline for unavailable clips

**Milestone:** Storage costs stay flat. All assets cleaned automatically.

---

## Phase 5 — Notifications

### Backend
1. Batched notification cron — collect activity per tape per user, fire every 3 hours
2. Immediate notification triggers — invite, share, Sync Push, tape deleted
3. Push delivery failure → email fallback
4. Store notification preferences per tape per user

### iOS
1. Per-tape notification preferences UI — on/off toggle, badge-only option
2. Badge count logic — silent increment when notifications off
3. Rich notification handling — tap routes to correct tape

**Milestone:** Users stay informed without fatigue.

---

## Phase 6 — .tape File Distribution

### Backend
1. Server validation on `.tape` file open — confirm identity, check permissions, initiate tracking

### iOS
1. `.tape` file generator — full manifest with all settings and cloud URLs
2. Present via iOS share sheet (WhatsApp, AirDrop, iMessage, email)
3. File open handler — parse `.tape`, validate with server, build tape on device
4. Non-user flow — App Store redirect → install → sign in → auto-build tape

**Milestone:** `.tape` files work as a viral acquisition channel.

---

## Phase 7 — Save to Device

### iOS (all iOS, no backend)
1. Save to Device option in share modal (visible when fully cached)
2. Reuse existing album creation logic
3. Save clips in timeline order — Live Photos as Live Photos, videos as videos, photos as photos

**Milestone:** Users can save shared tapes to Photos.

---

## Phase 8 — Polish

### Both
1. All error states — upload failed, connection lost, invite bounced, timeout, expired clip
2. All loading states — progress indicators for upload, download, sync status
3. Retry logic — exponential backoff, max 3 attempts
4. Graceful degradation — personal tapes work fully offline
5. Performance testing — simulate concurrent contributions
6. Full test suite — permission enforcement, housekeeping correctness

**Milestone:** Production ready.

---

## Build Order

Phases are sequential (each depends on the previous), but within each phase the backend and iOS tracks can run in parallel once the API contract is agreed.

```
Phase 1  ████████████  Foundation (backend + iOS in parallel)
Phase 2  ████████████  View Only Share
Phase 3  ████████████  Collaborative
Phase 4  ██████        Housekeeping (mostly backend)
Phase 5  ██████        Notifications
Phase 6  ████          .tape File
Phase 7  ██            Save to Device (iOS only, quick)
Phase 8  ████████      Polish
```

---

## Repos

| Repo | What | Tech |
|------|------|------|
| `tapes-ios` | iOS app (existing) | Swift, SwiftUI, AVFoundation |
| `tapes-api` | Backend API (new) | Cloudflare Workers (TypeScript), D1, R2 |

---

## Phase 1 Progress

- [x] Cloudflare account authenticated
- [x] Wrangler CLI installed
- [x] Scaffold Workers project with Wrangler
- [x] Create D1 database (`tapes-db`, region WEUR)
- [ ] Create R2 bucket (requires enabling R2 in Cloudflare Dashboard)
- [x] Define API contract (`docs/plan/API_CONTRACT_V1.md`)
- [x] Build D1 schema (6 tables, indexes, migrations applied locally)
- [x] Build all Workers API endpoints (auth, tapes, clips, collaborators, manifest, share, sync)
- [x] Build scheduled handlers (expiry, sync warning, orphan cleanup, notification batch)
- [x] Build iOS `TapesAPIClient` networking layer (actor, Keychain token storage)
- [x] Build iOS `CloudUploadManager` (background upload with retry)
- [x] Build iOS `TapeManifest` Codable model
- [x] Build iOS `KeychainHelper` for secure token storage
- [x] Build iOS `APIError` typed error handling
- [x] Update `AuthManager` with server token exchange
- [x] Register `tapes://` URL scheme in Info.plist
- [x] Register `.tape` UTI with file type association
- [x] Add push notification entitlement + background mode
- [x] Wire up deep link handler in `TapesApp`
- [ ] Create `tapes-api` repo on GitHub
- [ ] Deploy to Cloudflare (dev environment)
- [ ] End-to-end test: upload → record → manifest
