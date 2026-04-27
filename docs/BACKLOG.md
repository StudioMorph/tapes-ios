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

### 7. ~~`validateResetToken` response shape mismatch~~ — DONE

Fixed: Worker now returns `{ message: "Valid" }` to match the iOS `MessageResponse` type.

---

### 8. ~~Call `getMe` on app launch for auth state consistency~~ — DONE

Implemented: `AuthManager.refreshProfile()` calls `getMe` on every app launch (when signed in). Wired in `TapesApp.swift`'s `.task` block.

---

### 9. ~~Register endpoint should handle email send failure~~ — NOT AN ISSUE

The Shared and Collab tabs already show a "Verify your email" prompt with a "Resend Verification Email" button. If the initial email fails, the user has the resend action immediately visible. No fix needed.

---
