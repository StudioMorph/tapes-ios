# Pre-Release Fixes — Plans Index

This is the index for the pre-release cleanup plans — the "standards / security / hygiene" items flagged in the full-codebase review. Each item below has its own plan document. Plans are review artefacts, not execution tickets. Nothing is implemented until the plan is approved.

**Explicitly out of scope (handled separately):**
- Notification batching (its own task, agreed previously).
- Trial limit (`maxFreeTapes = 999`) and server-side tier enforcement — deliberate during internal testing; returning to these later.

**Where plans live:**
- iOS plans → `tapes-ios/docs/plan/`
- Backend plans → `tapes-api/docs/plan/`

Cross-repo plans (like the Mubert proxy) live in the repo that owns the primary change, and explicitly name the files affected in the other repo.

---

## Proposed execution order

The principle is: smallest blast radius first, build a working rhythm, defer the structurally risky until we've shipped a few green cycles. You approve each plan before I touch any code.

Plans marked **(iOS)** live in `tapes-ios/docs/plan/`. Plans marked **(backend)** live in `tapes-api/docs/plan/`. Cross-repo markdown links are unreliable — the paths below are authoritative.

### Phase 1 — Trivial hygiene (zero-risk one-liners)

1. **iOS code hygiene** — [iOSCodeHygiene.md](iOSCodeHygiene.md) **(iOS)**. Wire up `AppearanceConfigurator`, gate debug `print()`s, unify logger subsystems.
2. **Backend code hygiene** — `tapes-api/docs/plan/BackendCodeHygiene.md` **(backend)**. Dedupe `extractR2Key`, remove hardcoded team ID fallback, add security headers to the share landing page.

### Phase 2 — Small security fixes

3. **Apple token audience check** — `tapes-api/docs/plan/AppleTokenAudienceCheck.md` **(backend)**. Verify `aud` claim in `verifyAppleIdentityToken`.
4. **Universal-links domain** — [UniversalLinksDomain.md](UniversalLinksDomain.md) **(iOS)**. Align iOS Release base URL with the entitlement you have today.

### Phase 3 — Small correctness / UX fixes

5. **Share upload cache cleanup** — [ShareUploadCacheCleanup.md](ShareUploadCacheCleanup.md) **(iOS)**. Clear `pendingCreateResponse` on failure so retries start fresh.
6. **Mubert silent fallback removal** — [MubertSilentFallback.md](MubertSilentFallback.md) **(iOS)**. Replace the sine-wave WAV hack with a proper "music unavailable" path.

### Phase 4 — Data protection

7. **Clip media file protection** — [ClipMediaFileProtection.md](ClipMediaFileProtection.md) **(iOS)**. Add `FileProtectionType` to persisted media and `tapes.json`.
8. **Temp-dir video audit** — [TempDirVideoAudit.md](TempDirVideoAudit.md) **(iOS)**. Investigate clip-URL paths, close any purge-and-break gaps.

### Phase 5 — Backend hardening (design decisions first)

9. **JWT secret rotation** — `tapes-api/docs/plan/JWTSecretRotation.md` **(backend)**. Dual-secret verification + rotation procedure.
10. **Rate limiting middleware** — `tapes-api/docs/plan/RateLimitingMiddleware.md` **(backend)**. Enforce the limits the API contract already claims.

### Phase 6 — Bigger architectural work

11. **Mubert server-side proxy** — `tapes-api/docs/plan/MubertServerProxy.md` **(backend, cross-repo)**. Move customer ID + access token off-device.
12. **Test coverage baseline** — [TestCoverageBaseline.md](TestCoverageBaseline.md) **(both repos)**. The first real test layer.

### Phase 7 — Post-launch / deferred

13. **Push notification manager injection** — [PushNotificationManagerInjection.md](PushNotificationManagerInjection.md) **(iOS)**. Drop the singleton, inject dependencies.
14. **Root-level file reorganisation** — [RootLevelFileReorganisation.md](RootLevelFileReorganisation.md) **(iOS)**. Move residue files into the documented folder structure.
15. **Large file extraction** — [LargeFileExtraction.md](LargeFileExtraction.md) **(iOS)**. Split `TapeCompositionBuilder`, `TapePlayerViewModel`, `TapesStore`.

---

## How to use this directory

1. Read the plan for the next item.
2. Push back, question, correct, ask for alternatives.
3. Once you're happy, tell me "go" (or "execute", "commit", "merge").
4. I implement exactly what's in the approved plan. No scope creep. If I find something adjacent, I flag it — I don't fix it in the same commit.
5. We verify on device (your phone or Isabel's, depending on the change).
6. I commit and push. We move to the next.

If a plan turns out to be wrong once we start implementing, we stop, update the plan, and re-approve.

---

## What's not in this index

- **Notification batching** — has its own open plan work, being handled as its own task.
- **Trial caps and server-side tier enforcement** — deliberately disabled during internal testing, will be re-plan-ed closer to subscription work.
- **Subscription work generally** — downstream of the above.
- **The Android codebase** — not reviewed in this pass.
