# Universal Links Domain

**Status:** draft, awaiting approval.
**Scope:** iOS client URL config only. One small backend change to keep the `share_url` field internally consistent.
**Risk:** medium — universal links are a user-facing feature and misconfiguration means every shared link opens Safari instead of the app.
**Deploy posture:** iOS ships with next build. Backend deploy is independent.

---

## Problem

The Associated Domains entitlement on the iOS app lists exactly one domain:

```
applinks:tapes-api.hi-7d5.workers.dev
```

Meanwhile, [Tapes/Core/Networking/TapesAPIClient.swift:12](../../Tapes/Core/Networking/TapesAPIClient.swift:12) has:

```swift
#if DEBUG
private let baseURL = URL(string: "https://tapes-api.hi-7d5.workers.dev")!
#else
private let baseURL = URL(string: "https://api.tapes.app")!
#endif
```

In Release builds, share URLs are generated pointing at `api.tapes.app`. The entitlement doesn't include that domain. iOS will not treat `api.tapes.app/t/{id}` as a universal link — it will open in Safari, not the app. The landing-page HTML tries to bounce the user into the app via `tapes://t/{id}`, but that only works if the user installed the app after tapping the link, and it's a worse UX than the universal-link path.

Simplest, today: `api.tapes.app` isn't actually set up as a real host serving the AASA file. There's no DNS, no cert, no route. Even if we added it to the entitlement, it would 404. The only domain that currently works end-to-end is `tapes-api.hi-7d5.workers.dev`.

Therefore:

**Decision:** align the iOS Release base URL with the entitlement as-is. Use `tapes-api.hi-7d5.workers.dev` in both DEBUG and Release until we're ready to stand up `api.tapes.app` properly.

The long-term path (out of scope for this plan) is to actually host `api.tapes.app`: DNS to Cloudflare, Worker Routes configured, AASA cached under that hostname, add `applinks:api.tapes.app` to entitlements, ship a new iOS build. That's a separate piece of work for closer to the marketing-facing domain rollout.

---

## Fix

### Change 1 — Drop the Release-only URL branch

**File:** [Tapes/Core/Networking/TapesAPIClient.swift:9-13](../../Tapes/Core/Networking/TapesAPIClient.swift:9)

```swift
// Before
#if DEBUG
private let baseURL = URL(string: "https://tapes-api.hi-7d5.workers.dev")!
#else
private let baseURL = URL(string: "https://api.tapes.app")!
#endif

// After
/// The iOS Associated Domains entitlement must match this host exactly
/// for universal links to resolve into the app. See docs/features/UniversalLinks.md.
private let baseURL = URL(string: "https://tapes-api.hi-7d5.workers.dev")!
```

One URL. Same for DEBUG and Release. The entitlement matches. Universal links work.

### Change 2 — Comment in the entitlement file

Add a comment above the `applinks:` entry in the `.entitlements` file so future-me knows it's load-bearing. Associated Domains entries are plain strings, so the "comment" is really just a line in the accompanying PR/commit message — entitlements don't support XML comments reliably. Skip this, document in the `UniversalLinks.md` feature doc instead.

### Change 3 — Backend `share_url` sanity check

**File:** [src/lib/shareLinks.ts:4](../../../../Tapes-API/tapes-api/src/lib/shareLinks.ts:4) — `publicShareBase`.

Currently:

```ts
export function publicShareBase(request: Request, env: Env): string {
    const explicit = env.PUBLIC_SHARE_BASE?.trim();
    if (explicit) return explicit.replace(/\/$/, '');
    return new URL(request.url).origin;
}
```

This uses `PUBLIC_SHARE_BASE` if set, else the request origin. [wrangler.jsonc:27](../../../../Tapes-API/tapes-api/wrangler.jsonc:27) sets it to `https://tapes-api.hi-7d5.workers.dev`. Correct as-is. No change needed, but I've confirmed the `share_url` field that goes to iOS has the right host.

If `PUBLIC_SHARE_BASE` has drifted at any point (I don't see evidence it has), the link shown to the user would be inconsistent with the entitlement. Adding a note to the plan to verify before deploying.

---

## Risks

- **Share links created with the old Release URL will still exist in the wild.** Any user who copied a share link from a prior Release build onto e.g. a chat thread will have a `https://api.tapes.app/t/XYZ` URL. After this fix:
  - Tapping it on a device where the app is installed: still opens Safari (the entitlement doesn't cover `api.tapes.app`, same as today).
  - Tapping it on a device where the app isn't installed: Safari shows a site that doesn't resolve (DNS failure, or whatever `api.tapes.app` returns today).
  - This isn't a *regression* caused by this plan — it's the current state. But if users have bookmarked or shared links from Release builds, they're broken until `api.tapes.app` is stood up properly. We're currently pre-TestFlight, so the population of such links is zero. No mitigation needed now; note for later.
- **Debug and Release both hit the production Worker.** This is actually already the case for Debug today and has been working. No change in behaviour.
- **If someone adds `api.tapes.app` to the entitlement without setting up the host,** iOS will silently fail to verify universal links for that domain and log a warning. Doesn't break anything, but the entitlement change must be paired with a host that serves the AASA file.

---

## Verification

Five-minute test, two devices.

1. Build and install the Release configuration on your device.
2. Create a tape with a clip or two, open Share, copy the link. Verify the link shown is `https://tapes-api.hi-7d5.workers.dev/t/…`.
3. Paste the link into iMessage and send it to Isabel's device.
4. On Isabel's device, tap the link in iMessage. Expected: the Tapes app opens directly to the Shared tab and resolves the tape. Expected *not*: Safari opens.
5. On Isabel's device, long-press the link in iMessage — expected to show the "Open in Tapes" option in the preview menu.
6. Delete the Tapes app from Isabel's device. Tap the link again. Expected: Safari opens the landing page, which offers "Get Tapes on the App Store" and "Already installed? Open in app". This is the unhappy path and is fine.

If step 4 opens Safari instead of the app: the AASA file isn't being fetched or parsed correctly. Check `curl -s https://tapes-api.hi-7d5.workers.dev/.well-known/apple-app-site-association` — must return valid JSON with the right team ID and bundle ID. Verify the entitlement file (`Tapes/Tapes.entitlements`) lists `applinks:tapes-api.hi-7d5.workers.dev`. Apple caches AASA — toggling airplane mode, restart, or reinstalling the app forces a re-fetch.

---

## Deploy

No backend deploy required. This is a one-line iOS change. Ships with the next build.

---

## Open questions

- **When do we plan to stand up `api.tapes.app` properly?** Not for this plan — but worth naming as a future piece of work. It's the right marketing-facing domain for share links long-term.
- **Should we remove `api.tapes.app` references from docs for now?** The API_CONTRACT_V1.md doc mentions `api.tapes.app` as the production base URL. Updating those docs is trivial but a separate plan concern — the docs correctly describe the intended future state, just not reality today. Leave them as aspiration.
