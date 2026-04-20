# Share Upload Cache Cleanup

**Status:** draft, awaiting approval.
**Scope:** iOS only. Small audit + change in one file.
**Risk:** low. Bug fix in an error path.
**Deploy posture:** ships with next iOS build.

---

## Problem

In [Tapes/Core/Networking/ShareUploadCoordinator.swift](../../Tapes/Core/Networking/ShareUploadCoordinator.swift), the property `pendingCreateResponse` caches the server's `CreateTapeResponse` so subsequent share actions on the same tape (invite another collaborator, copy the link again, flip to collab) don't re-upload.

In `ensureTapeUploaded`, the cache is set in two places:

1. Early — immediately after the server create call (line ~180):
   ```swift
   response = try await api.createTape(...)
   self.pendingCreateResponse = response
   ```
2. Late — after successful upload + delta sync (line ~254):
   ```swift
   self.pendingCreateResponse = TapesAPIClient.CreateTapeResponse(
       ...
       clipsUploaded: true
   )
   ```

If the clip upload loop fails partway (say, the fifth of seven clips errors), the code takes the early-return at line ~249:

```swift
if !newFailures.isEmpty {
    self.uploadError = "\(newFailures.count) clip(s) failed to upload."
    self.finishUpload(success: false)
    return
}
```

At this point `pendingCreateResponse` still holds the *initial* create response from step (1). That response might have `clipsUploaded: false` (new tape) or `clipsUploaded: true` (existing tape). The `cachedCreateResponse(for:)` helper returns that value to the caller (e.g., `ShareLinkSection`).

**The bug:** if the user then retries via a different code path — say they close the Share modal, reopen it, and hit "Copy Link" — the share section may see `cachedCreateResponse != nil` and present the link as if everything is ready, when in reality some clips haven't been uploaded and recipients will see a tape with missing clips.

In practice this is narrow because most retry flows go back through `ensureTapeUploaded`, which re-computes the delta and re-uploads missing clips. But the state is internally inconsistent, and it's the kind of bug that bites when something in the stack changes.

---

## Fix

Two changes, both in `ensureTapeUploaded`:

### Change 1 — clear the cache on failure

In the failure branch (line ~246–250):

```swift
if !newFailures.isEmpty {
    self.uploadError = "\(newFailures.count) clip(s) failed to upload."
    self.pendingCreateResponse = nil       // ← new
    self.finishUpload(success: false)
    return
}
```

Also in the outer `catch`:

```swift
} catch {
    TapesLog.upload.error("Ensure upload failed: \(error.localizedDescription)")
    self.uploadError = error.localizedDescription
    self.pendingCreateResponse = nil       // ← new
    self.finishUpload(success: false)
}
```

### Change 2 — audit and document what the cache represents

Rename the concept slightly to make the invariant explicit. The cache now means "the tape is fully uploaded and all clips are on the server." That's what consumers should rely on. Two options:

**Option A (minimal change).** Keep the property name. Add a header comment explaining the invariant. Ensure every write to `pendingCreateResponse` happens only in success paths.

This means also dropping the *early* write at line ~180:

```swift
// Before
if let cached = self.pendingCreateResponse, cached.tapeId.lowercased() == tapeId {
    response = cached
} else {
    // ... makes POST /tapes
    response = try await api.createTape(...)
    self.pendingCreateResponse = response   // ← remove
}
```

Instead, store the `CreateTapeResponse` in a local variable within the function. Only persist to `pendingCreateResponse` at the end, after clips are confirmed uploaded:

```swift
// After
let response: TapesAPIClient.CreateTapeResponse
if let cached = self.pendingCreateResponse, cached.tapeId.lowercased() == tapeId {
    response = cached
} else {
    // ... makes POST /tapes
    response = try await api.createTape(...)
    // Do NOT cache yet — wait until clips are confirmed.
}

// ...clip upload loop...

// Success path only:
self.pendingCreateResponse = TapesAPIClient.CreateTapeResponse(
    tapeId: response.tapeId, ...,
    clipsUploaded: true
)
```

This means a tape's create-response isn't cached across runs unless the full upload succeeds. Second invocation after a partial failure re-calls `POST /tapes`, which is idempotent on the backend (returns 200 for existing tape) and re-computes delta. That's correct behaviour.

I'd go with **Option A**. It makes the invariant clean ("cached = fully uploaded"), it matches how `cachedCreateResponse(for:)` consumers use it, and it costs one extra `POST /tapes` call on retry after a partial failure — cheap.

### Change 3 — audit `seedCreateResponse`

[`seedCreateResponse`](../../Tapes/Core/Networking/ShareUploadCoordinator.swift:306) is called from the Share modal when it opens on a previously-shared tape. It primes `pendingCreateResponse` from a `GET /tapes/:id` response. That response doesn't have `clipsUploaded` — it's a different DTO. Currently `seedCreateResponse` takes a `CreateTapeResponse`, so callers must construct one.

Verify: does anywhere call `seedCreateResponse` with a response whose `clipsUploaded` is false or unknown? The purpose of the seed is "we already know this tape is on the server with its clips uploaded, skip the upload path." If the caller can't guarantee that, the seed is poisoning the cache.

This is an audit step, not necessarily a change. If the audit surfaces a case where the seed is wrong, the fix is small — either the caller stops seeding, or the seed path sets `clipsUploaded = true` explicitly.

---

## Risks

- **The extra `POST /tapes` on retry after partial failure** is a behaviour change. It's not visible to the user, and the backend's idempotent handling means no duplicate tape is created. But if there's a latency-sensitive path I haven't seen, the extra round-trip could be noticeable. Unlikely at the current scale.
- **Anything that currently reads `cachedCreateResponse` for its `clipsUploaded` flag** will see `nil` more often after this change instead of a partially-stale response. Consumers should treat `nil` as "not yet uploaded" and `non-nil` as "fully uploaded" — which is what the invariant now says. Audit call sites to confirm.

---

## Verification

1. Reproduce the bug: intentionally fail a mid-upload (simplest way: disable Wi-Fi right as the upload progresses, or use a simulator with Network Link Conditioner set to 100% packet loss). Check the Share modal state after failure — is the link shown as ready? Today, yes (bug). After fix: no.
2. Happy path: share a tape normally end-to-end on your device, receive on Isabel's. Confirm nothing regressed.
3. Retry path: fail once, retry, confirm full re-upload completes and recipient receives everything.
4. Modal re-open path: share a tape successfully, close the modal, re-open it, confirm the link is immediately ready (no re-upload) — the cache should hold for a fully-uploaded tape.

---

## Deploy

None. iOS-only, ships with next build.

---

## Open questions

- Should we show a more specific error to the user ("3 of 7 clips failed, tap retry to try again") instead of the current "\(n) clip(s) failed to upload"? Out of scope for this plan. Copy decision, not a bug.
- After a partial failure, does the UI offer a retry affordance? Worth checking while we're in this area, but not in scope unless it's broken.
