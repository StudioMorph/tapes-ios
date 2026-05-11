# Backlog

Items to revisit when time allows. Not urgent, not blocking — just worth doing.

---

## Sharing

### 1. Preserve receiver's custom tape title on re-sync

**Context**: When a receiver renames a shared tape locally and later taps the same share link to pick up new clips, the download coordinator overwrites their custom title with the sender's title from the manifest.

**Fix**: Skip the title update during merge if a local tape already exists (returning receiver). The sender's title should only be applied on the initial download. The receiver's local rename is "theirs" to keep.

**Files likely involved**: `SharedTapeDownloadCoordinator.swift`

---

### 10. Parallel clip uploads (2–3 concurrent) + bounded extraction prefetch

**Context**: After the upload pipeline optimisation work (`docs/features/UploadPipelineOptimisation.md`) the dominant remaining cost on slow networks is per-clip TLS handshake + first-byte latency. Each clip currently runs through its `createClip → PUT R2 → confirmUpload` pipeline serially against the next clip; while one stream is idle waiting on the network, the upload pool sits empty. Within-clip parallelism is shipped (primary + paired Live Photo movie + thumbnail run concurrently); cross-clip parallelism is not.

**Expected win**: 1.5–2.5× total upload time on cellular for tapes of 10+ clips. Smaller (1.2–1.5×) on Wi-Fi where bandwidth is the bottleneck. Compounds with the within-clip parallelism we already shipped.

**Plan summary** (not yet approved):

- Replace the per-clip sequential `for` loop in `ensureTapeUploaded` and `contributeClips` with a bounded concurrent pool. Constant ceiling of 3 in flight; do not introduce dynamic Wi-Fi/cellular tuning before TestFlight.
- Extend the extract-ahead prefetch from depth 1 to depth N+1 (one ahead of the in-flight pool size). Memory cost is now negligible because every payload type is file-backed (the file-streaming follow-up landed in `f7bf622`); the real ceiling is disk space in `tmp/` for the export-session fallback.
- Update progress UX from "Uploading clip X of Y" to a completed-count form ("Uploaded X of Y") because in-flight indices stop being meaningful.
- Cancellation path: if any clip exits with an error after `withRetry` exhaustion, cancel siblings still in flight, surface failures via `failedClipIndices` (already a `Set` so insert order doesn't matter), end the batch.

**Pre-flight checks needed before implementing**:

- Verify Cloudflare Worker rate limits allow 3 concurrent `confirmUpload` calls per tape without 429s. If they don't, raise the limit on the relevant rate-limit namespace before iOS work starts.
- Confirm `confirmUpload` is order-independent server-side (very likely — each clip is its own row — but worth checking once).
- Test on both Wi-Fi and cellular before declaring done; concurrency wins are network-shaped and we don't want a regression hidden by good office Wi-Fi.

**Trigger**: Defer until either (a) we have a few uninterrupted days for performance work + cross-network testing pre-TestFlight, or (b) post-TestFlight when real users complain about long upload times. Do not bundle with unrelated work — concurrency bugs are the hardest to debug and warrant a clean diff.

**Risks**:

- Concurrency introduces non-deterministic failure ordering; harder to reproduce regressions.
- Backend rate limits could throttle us into worse-than-serial throughput if not raised first.
- `BGContinuedProcessingTask` interaction is unknown — denser progress updates *might* delay expiration (good) or might trip system limits (bad). Has to be measured.

**Files likely involved**: `Tapes/Core/Networking/ShareUploadCoordinator.swift` (the concurrent pool, prefetch depth, progress UX), `tapes-api/src/middleware/rateLimit.ts` (if limits need raising), `docs/plan/UploadPipelineParallelClips.md` (to be written when we execute).

---

## App Settings

### 2. Create a dedicated settings view

**Context**: The app currently has no standalone settings screen. As features grow (sharing, sync, notifications), a dedicated settings view is needed to house user preferences.

---

### 3. Auto-update on Wi-Fi only toggle

**Context**: Collaborative tapes will auto-check for updates on app open. To avoid unexpected cellular data usage, add a "Auto-update on Wi-Fi only" toggle in the settings view. When enabled, manifest checks still happen on any connection but clip downloads are deferred until Wi-Fi.

**Depends on**: Backlog item #2 (settings view).

---

## Infrastructure

### 4. Pre-TestFlight: protected deploy flow (staging Worker)

**Context**: There is currently no staging environment. Every `wrangler deploy` replaces production instantly. During pre-TestFlight internal testing that's acceptable — the only users affected are Jose and Isabel on their own devices. Once external testers or App Store users exist, a bad deploy is visible within seconds and there is no checkpoint to catch it first.

**Trigger**: Must be completed before TestFlight submission.

**Plan summary** (approved, awaiting implementation):

- Second Cloudflare Worker at `tapes-api-staging.hi-7d5.workers.dev`, separate D1 database `tapes-db-staging`, separate R2 bucket `tapes-media-staging`. Separate `JWT_SECRET` and rate-limit namespace IDs (`2001..2004`). Shared Apple/APNs/Mubert/CF credentials (same accounts).
- `wrangler.jsonc` restructured into explicit `env.staging` and `env.production` blocks. `wrangler deploy` with no `--env` flag must error out — every deploy is a conscious choice of target.
- iOS `TapesAPIClient.baseURL` reintroduces a `#if DEBUG` split: DEBUG builds hit staging, Release hits prod. `Tapes.entitlements` adds `applinks:tapes-api-staging.hi-7d5.workers.dev` alongside the existing prod host.
- Deploy flow becomes: apply migration to staging → deploy staging → smoke-test → apply migration to prod → deploy prod → verify on device.

**Known limitations**:
- Staging starts empty — schema changes whose behaviour depends on populated data still only surface on prod.
- Testing the DEBUG build on device wipes local tape data on each install swap (cloud-backed tapes come back on next sign-in; purely local tapes do not).
- Isabel's device needs its own DEBUG install to participate in cross-device staging tests.

**Files likely involved**: `tapes-api/wrangler.jsonc`, `tapes-api/src/types/env.ts` (no new fields), `tapes-ios/Tapes/Core/Networking/TapesAPIClient.swift`, `tapes-ios/Tapes/Tapes.entitlements`.

**Detailed plan**: to be written at `tapes-api/docs/plan/StagingWorkerSetup.md` when we execute.

---

### 5. R2 content deduplication across tapes

**Context**: When the same photo or video is added to multiple tapes, the media bytes are uploaded to R2 separately each time. Each tape creates clips with unique UUIDs, so the server treats them as independent objects — no cross-tape awareness of duplicate content.

**Impact**: Redundant upload bandwidth and R2 storage costs. Noticeable when a user creates several tapes from the same photo library selection.

**Approach**: Content-addressable storage — hash the media file before upload, check if the hash already exists in R2, reuse the existing object if so. Requires reference counting so the expiry/cleanup cron knows when an R2 object is safe to delete (i.e., no remaining clips reference it).

**Files likely involved**: `ShareUploadCoordinator.swift` (iOS — hash before upload), `tapes-api/src/routes/clips.ts` (server — dedup check on `createClip`/`confirmUpload`), `tapes-api/src/routes/scheduled.ts` (cleanup — reference counting).

---

## Localization

### 6. Localize the app with String Catalogs and add Portuguese

**Context**: All user-facing strings are hardcoded in English. Apple's String Catalog system (`.xcstrings`) provides type-safe, compiler-checked localization with auto-generated Swift symbols.

**Plan**:
- Enable String Catalog Symbol Generation (already toggled in project settings).
- Create a `.xcstrings` catalog file.
- Extract all user-facing strings (~100-200) across views, sheets, alerts, badges, and buttons into the catalog.
- Replace hardcoded strings with catalog references throughout the codebase.
- Add Portuguese (PT) translations for all keys.
- Review translations for tone — some terms (Tape, Clip, Mood, Live Photo) may be better kept in English.

**Scope**: Touches almost every view file. Mechanical but large. Half-day project. No logic changes — purely additive.

**Files likely involved**: New `.xcstrings` file, all files under `Tapes/Views/`, `Tapes/Components/`, `Tapes/Features/`, `Tapes/Export/ExportDialogs.swift`, `Tapes/DesignSystem/`.

---

## Authentication

### 15. Implement refresh tokens for silent session renewal

**Context**: JWT session tokens now last 1 year (extended from 7 days). This is a pragmatic shortcut so users stay signed in indefinitely, matching consumer-app expectations (Instagram, TikTok, etc.). The trade-off is that a stolen token is valid for up to a year.

**Proper approach**: split into a short-lived access token (15 min–1 hour) + a long-lived refresh token (6–12 months, stored in Keychain). When the access token expires, the app silently hits a `/refresh` endpoint, gets a new access token, and retries the original request. The user never sees a sign-in screen. Refresh tokens can be revoked server-side (account deletion, security incident) without invalidating all sessions globally.

**Files likely involved**: `tapes-api/src/lib/jwt.ts`, `tapes-api/src/routes/auth.ts` (new `/refresh` endpoint, refresh token minting on login/register), `Tapes/Core/Networking/TapesAPIClient.swift` (401 interception + automatic retry with refresh), `Tapes/Core/Auth/AuthManager.swift` (Keychain storage for refresh token, auto-sign-out on refresh failure).

**Trigger**: post-launch. The 1-year token is fine for now. Revisit if/when we have reason to believe tokens are being stolen or when we need server-side session revocation.

---

### 7. ~~`validateResetToken` response shape mismatch~~ — DONE

Fixed: Worker now returns `{ message: "Valid" }` to match the iOS `MessageResponse` type.

---

### 8. ~~Call `getMe` on app launch for auth state consistency~~ — DONE

Implemented: `AuthManager.refreshProfile()` calls `getMe` on every app launch (when signed in). Wired in `TapesApp.swift`'s `.task` block.

---

### 9. ~~Register endpoint should handle email send failure~~ — NOT AN ISSUE

The Shared and Collab tabs already show a "Verify your email" prompt with a "Resend Verification Email" button. If the initial email fails, the user has the resend action immediately visible. No fix needed.

---

## Subscription / Monetisation

### 11. Watermark on export (Free tier)

**Context**: The new Tapes Plus paywall promises "No Watermark on export" as a Plus benefit, which implies Free exports carry one. The watermark itself is not yet in the export pipeline.

**Plan summary** (not yet approved): overlay a small "Made with Tapes" wordmark in a fixed corner of the composition during `AVAssetExportSession` setup, gated by `entitlementManager.isFreeUser`. Needs decisions on placement, opacity, scaling for portrait vs landscape exports, and whether it animates or sits static. Likely a `CALayer` composited via `AVVideoCompositionCoreAnimationTool`.

**Files likely involved**: `Tapes/Export/ExportCoordinator.swift`, the underlying `AVMutableComposition` setup helpers, and a new asset for the wordmark.

**Trigger**: tackle alongside any other export-pipeline overhaul — touching the composition graph for one isolated feature is more risk than reward.

---

### 12. Server-side persistence of activation count

**Context**: Free-tier "5 activated tapes lifetime" cap is currently per-install (UserDefaults). A reinstall resets the count, which is fine for now but trivially exploitable.

**Approach**: Move `activatedTapeIDs` to the server keyed by Apple ID once user accounts carry monetisation state. iOS reads the count on launch and writes through on every `markTapeActivated`. Local set becomes a cache with last-known-good fallback for offline.

**Files likely involved**: `tapes-api/src/routes/`, `Tapes/Core/Subscription/EntitlementManager.swift`.

**Trigger**: post-launch, once we have evidence that the per-install cap is being routinely bypassed.

---

## Background music sharing

### 13. Owner can update background music after first share

**Context**: Background music is write-once on the server (`docs/features/BackgroundMusic.md` § Sharing & Sync). Once attached, the owner cannot change the track for receivers — only the local copy mutates. The server has no update endpoint deliberately.

**Trigger to revisit**: real users complain "I changed the music but my collaborators still hear the old one."

**Approach**: add `PUT /tapes/:id/music` (owner-only) that re-runs the prepare/confirm flow without the 409 backstop. iOS would call it whenever the owner mutates `tape.backgroundMusicMood` on a tape whose `shareInfo` is non-nil. Receiver guard stays as-is — local customisation still wins.

**Files likely involved**: `tapes-api/src/routes/music-share.ts`, `Tapes/Core/Networking/TapesAPIClient.swift`, somewhere in the music-selection flow on iOS to detect "this tape is shared, push the change".

---

### 14. ~~Mubert library track redistribution licensing~~ — DONE

Resolved by referencing library tracks by Mubert track ID instead of re-hosting them on R2. Receivers resolve the ID to a fresh playback URL via the existing `/music/tracks/:id` worker proxy. See `docs/features/BackgroundMusic.md` § Sharing & Sync.

---
