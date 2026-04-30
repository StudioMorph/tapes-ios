# Subscription Tiers — Free vs Plus

## Summary

Two-tier model: **Tapes Free** (default) and **Tapes Plus** (paid). Free is gated at four points; Plus removes all four gates.

## Purpose & Scope

- Define the access matrix between the two tiers.
- Document where, why, and how each free-tier gate fires in the UI.
- Capture the on-device counter that powers the share/collab cap.

## Tier matrix

| Capability | Free | Plus |
|---|---|---|
| Create personal tapes (My Tapes) | Unlimited | Unlimited |
| Add clips to existing personal tapes | Unlimited | Unlimited |
| Share or activate a collab tape | **5 lifetime** | Unlimited |
| Re-share an already-activated tape | Unlimited | Unlimited |
| Background music — Moods *(currently dormant)* | n/a | n/a |
| Background music — 12K Library | First **1,000 tracks** | All 12,000 |
| Background music — AI Prompt | Locked | Unlocked |
| Ads during playback | Yes | No |
| Watermark on export | *(planned, see backlog)* | None |

## The activation counter

The Free-tier "5 lifetime" cap is enforced as a **set of activated tape UUIDs**, not a raw integer. Storing IDs (rather than a count) gives three guarantees:

1. **No double-counting.** A tape that's been both shared and turned into a collab is still one entry.
2. **Re-shares don't cost anything.** Once a tape is in the set, every subsequent share/recipient/edit on that tape is free of the gate.
3. **Reliable grandfathering.** On first launch of the build that ships these gates, every tape currently shared or marked collab is inserted into the set (one-time pass, flagged in UserDefaults). Test devices that already have ≫5 active tapes don't suddenly break.

### Storage

- Key: `monetisation.activatedTapeIDs.v1` — `[String]` of UUIDs.
- Migration flag: `monetisation.didMigrateActivatedTapeIDs.v1` — `Bool`.
- Lives in standard `UserDefaults`. Per-install only — wiped on app delete. Server-side persistence is logged in `docs/BACKLOG.md` for post-launch.

### Activation increment points

The set is added to wherever the user takes a deliberate share / collab action. All sites are idempotent — a tape that's already in the set is a no-op.

**Sharing a tape (any of the following):**

1. **Copy Link** — `ShareLinkSection.copyLinkTapped`, after the URL is placed on the clipboard. By the time the "Link copied" toast fires the user has clearly committed; we can't tell if they actually paste it.
2. **System share sheet completed with a destination** — `ShareLinkSection.shareLinkTapped` → `ShareActivityView.onCompleted`. Fires only when `completed == true` *and* `activityType != nil` (i.e. they picked Messages/Mail/AirDrop/etc. and the OS-level share went through). Swipe-to-dismiss does **not** count.
3. **Email invite sent** — `ShareLinkSection.inviteTapped`, after `inviteCollaborator` returns successfully. Most deliberate of the three: the user typed a specific recipient.

The same three triggers fire in the post-upload dialog (`SharePostUploadDialog`) for the case where the user dismissed the upload modal mid-share and is finishing from the lightweight follow-up sheet.

**Activating a collab tape:**

4. **First clip on an empty Collab tape** — `TapeCardView.checkAndCreateEmptyTapeIfNeeded`. Adding the first clip to a `tape.isCollabTape` placeholder commits a brand-new collab tape; that's an unambiguous activation.

**What does *not* increment:**

- Tape upload alone (`ensureTapeUploaded` success). Uploading is just "the tape exists on the server"; a user can open the share sheet, upload, then close without sharing with anyone. We never count for that.
- Tapping Copy Link → opening the share sheet → dismissing it without picking a destination.
- A recipient opening the share link or contributing — currently *not* a trigger because the iOS app doesn't poll for remote view events. If we add that signal later it's a backlog candidate; the current model is "count when the user *acts*", not "when the recipient acts".

## Gate sites

All four gates present the same `PaywallView` sheet — there's no tier-specific UI variant.

### 1. Share triggers inside the Share modal (Copy Link, Share Link, "Secured by email" toggle)

- **Why not the share button on the card?** `ShareModalView` hosts both `ShareLinkSection` (sharing) *and* the merge/save export flow. Gating the icon would block users from reaching their own export. So the icon always opens the modal; the gate fires inside, on the actual share triggers.
- **Where:** `ShareLinkSection.passesActivationGate()`, called from `copyLinkTapped`, `shareLinkTapped`, and `securedByEmailBinding` (the toggle).
- **Behaviour:** if the tape isn't yet in the activation set and the user is at the cap, paywall opens and the action is refused. Already-activated tapes always pass. The "Secured by email" toggle stays OFF if the gate fires, mirroring the AI Prompt segment pattern (early discovery — user doesn't see the email form, type an address, *then* get blocked).
- **Visual:** the share icon on the card is unchanged. The `ShareModalView`'s merge / export section is always reachable.
- Received tapes (`SharedTapesView`) hard-disable the share affordance, so no gate is needed there.

### 2. Empty Collab tape — Media picker / Camera

- **Where:** `TapeCardView.handlePlaceholderTap(_:)` and the FAB `gallery` / `camera` action handlers.
- **Behaviour:** only triggers when `tape.isCollabTape && tape.clips.isEmpty && !tape.hasReceivedFirstContent`. Adding a first clip would create a new collab activation; if the user is at the cap, paywall opens instead. Empty My-Tapes placeholders are never gated — only collab.
- **Plumbing:** `TapeCardView` exposes `onActivationBlocked: () -> Void`. `CollabTapesView` flips its `showingPaywall` when this fires.

### 3. AI Prompt segment

- **Where:** `BackgroundMusicSheet.pickerBinding`.
- **Behaviour:** the segmented picker uses an intermediary `Binding<Tab>`. When a Free user taps the AI Prompt segment, the setter shows `PaywallView` and refuses the change — the segment visibly snaps back to its previous selection.
- **Why this shape:** keeps the segment Apple-native (no custom segmented control) and avoids any half-loaded AI Prompt UI flashing on screen.

### 4. 12K Library — 1,000-track cap

- **Where:** `LibraryBrowserViewModel.loadTracks(api:reset:trackCap:)`.
- **Behaviour:** pagination stops once `tracks.count >= cap`. The cap is read from `entitlementManager.libraryTrackCap` (`1000` for Free, `nil` for Plus). Filter `tracksCount` values come straight from Mubert — they reflect the **true** library size, not the capped slice. We don't want to mislead Free users about how big the library actually is.
- **Bottom toolbar:** `LibraryBrowserView` overlays `safeAreaBar(edge: .bottom)` (iOS 26+, falls back to `safeAreaInset` on earlier) with a borderedProminent capsule button labelled "Upgrade to unlock 12,000 tracks". Toolbar is hidden for Plus.

## Migration on first launch

`TapesApp.body.task` calls `entitlementManager.migrateActivatedTapeIDs(from: tapeStore.tapes)` once per install. Walks `tapesStore.tapes`, inserts every `tape.isShared || tape.isCollabTape` ID into the activation set. Sets `monetisation.didMigrateActivatedTapeIDs.v1` so the walk never repeats.

## Plus → Free regression

Subscription cancellation makes `accessLevel` flip back to `.free` on the next StoreKit refresh. We **don't** clear the activation set on the way down — every tape that was shared while on Plus stays grandfathered. The user starts back at whatever count they reached. If that's > 5, every existing shared/collab tape continues to work; only *new* activations are gated.

## Files

| File | Role |
|---|---|
| `Tapes/Core/Subscription/EntitlementManager.swift` | Counter, gates, migration helper. Single ask-point for all access checks. |
| `Tapes/TapesApp.swift` | Calls `migrateActivatedTapeIDs` on launch. |
| `Tapes/Views/Subscription/PaywallView.swift` | The sheet presented by every gate. |
| `Tapes/Views/TapesListView.swift` | Opens the share modal for My Tapes. No gate — the share modal hosts export too, which must remain reachable. |
| `Tapes/Views/Share/CollabTapesView.swift` | Opens the share modal for Collab tapes. Hosts the paywall sheet for the empty-collab gate via `TapeCardView.onActivationBlocked`. |
| `Tapes/Views/TapeCardView.swift` | Gates `FabSwipableIcon` (gallery/camera) and `handlePlaceholderTap` on empty collab tapes. Marks tape activated when first clip lands. |
| `Tapes/Views/Share/ShareLinkSection.swift` | Hosts the gate (Copy Link, Share Link, "Secured by email" toggle) and marks tape activated on the three deliberate share triggers. Owns its own paywall sheet. |
| `Tapes/Views/Share/ShareUploadOverlay.swift` | Marks tape activated on the post-upload dialog's Copy / Share Now actions. No gate — these only appear after the user already passed the gate at the original button. |
| `Tapes/Views/BackgroundMusicSheet.swift` | Hosts paywall sheet, gates AI Prompt segment via picker binding interception. Wires `onUpgradeTapped` for the library toolbar. |
| `Tapes/Views/LibraryBrowserView.swift` | Threads `trackCap` into the view model, renders bottom upgrade toolbar for Free. |

## Out of scope

Two paywall benefits listed in `PaywallView` are *not* implemented in this pass and are tracked in `docs/BACKLOG.md`:

- **Watermark on export** (item 11) — touches the export composition graph; deferred to the next export-pipeline pass.
- **Server-side activation persistence** (item 12) — UserDefaults is the per-install solution until accounts can carry monetisation state.

Ad-free playback is already correctly tied to `entitlementManager.isPremium` in `TapePlayerViewModel.isFreeUser` — no change needed for this pass.

## QA / Test plan

Manual verification on device, signed out of any active sandbox subscription:

1. Share 5 distinct My Tapes → 6th share-button tap → paywall.
2. Share the same tape twice → counter still 1 (set semantics).
3. Mix 3 view-only shares + 2 collab tapes (5 total) → next share *or* next collab placeholder tap → paywall.
4. With migration in place, tapes that were already shared before the build update keep opening their share sheet without paywall, even if the count is over 5.
5. Open Background Music sheet → tap AI Prompt segment → paywall opens, segment stays on Library.
6. Scroll the 12K Library to the end → exactly 1,000 tracks → bottom upgrade toolbar visible → tap → paywall.
7. Subscribe via sandbox → all four gates disappear; bottom toolbar disappears.
8. Cancel sandbox subscription → relaunch → gates return; activation set persists.

Reset for testing: deleting the app between tier flips clears UserDefaults and the activation set.

## Related documents

- Implementation plan: `docs/plan/free-tier-paywall-gates.md`
- Background music feature: `docs/features/BackgroundMusic.md`
- Auth + subscription overview: `docs/features/AuthAndSubscription.md`
- Backlog: `docs/BACKLOG.md` (items 11 and 12)
