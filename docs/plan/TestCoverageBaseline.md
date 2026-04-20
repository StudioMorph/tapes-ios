# Test Coverage Baseline

**Status:** draft, awaiting approval. This is a **proposal** — unlike other plans, it's setting direction for ongoing work rather than a single landable change.
**Scope:** both repos. New test files.
**Risk:** writing tests doesn't create runtime regressions. But tests will surface real bugs — expect follow-up fixes.
**Deploy posture:** no deploy step. Tests run in CI (once we have CI) and locally.

---

## Problem

Current state:

- **iOS tests:** [TapesTests.swift](../../TapesTests/TapesTests.swift) is a stub (`func example() {}`). [SnapMathTests.swift](../../TapesTests/SnapMathTests.swift) tests a helper function defined in the test file itself — not the production `SnappingHScroll.Coordinator.scrollViewWillEndDragging` math. [TapeCompositionBuilderTests.swift](../../TapesTests/TapeCompositionBuilderTests.swift) is the one file that exercises real production code. UITests are boilerplate stubs.

- **Backend tests:** `tapes-api/test/index.spec.ts` and `env.d.ts` exist. Haven't read `index.spec.ts` in depth; worth confirming what's there.

For a public release of an app that will handle real user data, real auth, real money (subscriptions), this is a liability. Not a TestFlight blocker — no one rejects for lack of tests — but it's the single biggest risk of undiscovered regressions shipping to users.

---

## Approach

**Not trying to hit a coverage percentage.** That's the wrong goal. Goal is: *every critical path has at least one test that breaks when the critical path breaks.* Then we expand from there.

**Not rewriting the test scaffolding.** Swift Testing for new iOS tests; Vitest for backend (already configured).

**Tests run locally on every engineer's machine.** No CI this week. Writing CI is its own plan. Meanwhile, we establish the discipline that every change runs the relevant tests.

---

## Priority list

### iOS — Tier 1 (write first)

**1. Tape persistence round-trip.**

- `TapesStore` saves a tape with `N` clips → disk.
- Re-instantiate `TapesStore`.
- Confirm the loaded tape matches the saved tape exactly (including sparse encoding semantics: default-valued fields are omitted from JSON but restored on decode).
- Include a clip with an `imageData` blob; confirm the blob is written to `clip_media/<id>_image.dat` and restored on load.
- Include placeholder clips; confirm they're stripped before save and the empty-tape invariant restores them on load.

Why first: it's the foundation. If persistence is broken, everything is broken. And the sparse-encoding invariant is the kind of thing that silently drifts if no test pins it down.

**2. Manifest decode.**

- Given a hand-crafted JSON matching the `TapeManifest` shape, confirm `JSONDecoder().decode(TapeManifest.self, …)` succeeds.
- Include all optional fields (`live_photo_movie_url`, `contributor_name`, `ken_burns`).
- Verify missing optional fields don't break decode.
- Verify that unknown fields in the JSON are ignored (forward compat).

Why: recipient download breaks if the server adds a field and iOS rejects the response. This test pins the contract.

**3. Share upload cache invariant.**

- Simulate `ShareUploadCoordinator.ensureTapeUploaded` with an injected mock API that fails mid-upload.
- Assert `pendingCreateResponse` is `nil` after the failure.
- Run the same flow succeeding; assert `pendingCreateResponse` has `clipsUploaded: true`.

Why: the bug from the [ShareUploadCacheCleanup plan](ShareUploadCacheCleanup.md) needs a test pinning the fix.

**4. Subscription tier resolution.**

- `SubscriptionManager.refreshSubscriptionStatus()` with no transactions → `activeTier == nil`.
- With a `plus.monthly` transaction → `activeTier == .plus`.
- With a `together.annual` transaction → `activeTier == .together`.
- With both (user upgraded mid-month) → `activeTier == .together` (bigger wins).
- With an expired transaction → ignored.

Why: subscription gating is about to become real. Getting this wrong means free users get premium, or paid users get downgraded. A broken `SubscriptionManager` is invisible to developers until a user complains.

**5. Upload badge delta math.**

- `Tape.pendingUploadCount` with `lastUploadedClipCount == nil`, `clips.count == 3` → 0.
- `lastUploadedClipCount == 3`, `clips.count == 5` → 2.
- `lastUploadedClipCount == 5`, `clips.count == 3` (user deleted clips) → 0 (not negative).
- `lastUploadedClipCount == 3`, `clips.count == 3 + N placeholders` → 0 (placeholders excluded).

Why: badges are user-visible. Wrong badges erode trust.

### iOS — Tier 2 (next)

**6. Production snap math.**

`SnappingHScroll.Coordinator.scrollViewWillEndDragging` has real math. Extract it into a testable pure function (takes proposed offset, item width, container width, content width → target offset and snap index). Port the existing SnapMathTests to test the real function.

Why: the existing tests don't test the real code. The carousel is the app's signature interaction. It deserves pinned math.

**7. Clip insertion position math.**

Multi-clip insert at carousel "center" — the between-index math documented in the Runbook. Given a clip count and a red-line position, test the resulting insertion index is correct.

**8. Tape duration computation with transitions.**

`Tape.duration` with varying clip counts, transition durations, and transition styles. Confirm the subtraction-for-overlap math is right, especially for `.none` vs the slide/crossfade variants.

### Backend — Tier 1 (write first)

**9. Apple token audience check.**

- Given a valid token with wrong `aud` → returns null.
- Given a valid token with right `aud` → returns payload.
- Given an expired token → returns null.
- Given a malformed token → returns null.
- (Mock the JWKS fetch and signature verification; this test is about the payload-validation logic.)

**10. Share resolution for all four variants.**

- Given a `view_open` share ID, an auto-join happens for an unauthenticated collaborator.
- Given a `view_protected` share ID and a matching email invite → invite activates.
- Given a `view_protected` share ID and *no* matching invite → 403.
- Same four cases for `collab_*`.

These are the pathways through `resolveShare`. Miss a branch, a real user lands on a 403 they shouldn't.

**11. Sync status query.**

- Given a user with 2 shared tapes, one with 3 pending downloads and one with 0 → response has only the first tape, count 3.
- Given an empty `tape_ids` array in the request → returns all tapes with pending > 0.
- Given tape IDs the user doesn't belong to → not in response.

**12. Presigned URL signing.**

- Given a clip key and R2 options, `generatePresignedUploadUrl` returns a URL with `X-Amz-Signature` and `X-Amz-Expires=3600`.
- Same for download.
- Signature is non-empty (sanity check — we can't verify AWS signature math offline).

### Backend — Tier 2 (next)

**13. Collaborator revoke scoping.**

- Revoke on `collab_protected` does not affect `view_protected` invite for the same email.
- Revoke on all variants clears download tracking.

**14. Notification batching flush query.**

Once the batching plan ships, a test for the flush: seed a queue row, advance time via a freezer (test helper), call the handler, confirm the row is processed and deleted.

**15. Device token update.**

`PUT /users/me/device-token` with valid token → DB updated. Without → 422.

---

## How to structure

**iOS:** move existing `TapesTests.swift` stub aside. Create:
- `TapesTests/Persistence/TapesStoreTests.swift`
- `TapesTests/Persistence/ClipEncodingTests.swift`
- `TapesTests/Networking/ManifestDecodeTests.swift`
- `TapesTests/Networking/ShareUploadCoordinatorTests.swift`
- `TapesTests/Subscription/SubscriptionManagerTests.swift`
- `TapesTests/Models/TapeTests.swift`
- `TapesTests/Components/SnapMathTests.swift` (replacing the current file's logic)

Use Swift Testing (`@Test`, `#expect`) throughout new tests. Keep existing XCTest infrastructure for `TapeCompositionBuilderTests` (no need to port).

**Backend:** expand `test/index.spec.ts` or split into `test/auth.spec.ts`, `test/share.spec.ts`, `test/sync.spec.ts`, `test/rate-limit.spec.ts`. Vitest with `@cloudflare/workers-types` for `env` mocking. D1 is the hardest part — we use in-memory SQLite with matching schema (running the migrations against the test DB in a `beforeAll`).

---

## Cadence

**Milestone 1 (week 1):** iOS Tier 1 (items 1-5). Deliverable: tests run locally, pass.

**Milestone 2 (week 2):** Backend Tier 1 (items 9-12). Deliverable: tests run via `npm test`, pass.

**Milestone 3 (week 3):** iOS Tier 2 (items 6-8) + Backend Tier 2 (items 13-15). Plus first CI pipeline (GitHub Actions running the existing tests on PR).

These are my suggested milestones; you decide what's realistic alongside the rest of the pre-release work.

---

## Expected findings

Writing tests will surface bugs. I'd bet on these, based on the codebase review:

- Persistence round-trip test (item 1) may surface at least one sparse-encoding field that doesn't round-trip correctly (some `decodeIfPresent` fallback defaulting to the wrong value).
- Subscription tier test (item 4) may surface an ordering bug in how `plus` vs `together` are resolved when both are present.
- Share resolution test (item 10) may surface an edge case in the `view_protected` email-matching path.

Every surprise is a win — better now than in App Review.

---

## Risks

- **Tests take time.** This is ongoing work that runs alongside launch prep. Non-trivial engineer-time investment.
- **Tests can be false-positive if they mock too aggressively.** Guideline: mock the network boundary only. Real `TapesStore`, real `SubscriptionManager`, real code paths everywhere else.
- **Tests can rot.** If a test fails and someone "fixes" it by commenting it out, we're worse off than before. Policy: no skipping, no commenting. Fix the code or fix the test, don't silence it.

---

## Deploy

No deploy. Tests run locally, later in CI.

---

## Open questions

- Do we want CI (GitHub Actions) in scope for this plan, or a separate plan? Recommend separate — the CI setup has its own decisions (secrets, Xcode version pinning, cost).
- Swift Testing requires Xcode 16+. We're already on Xcode 16+. Good.
- Should we set a pass-rate quality gate (block merges on test failures once CI exists)? Obviously yes, eventually. Not for this plan.
