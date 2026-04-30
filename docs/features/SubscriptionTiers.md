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

The set is added to in two places, both idempotent:

1. **`ShareLinkSection.finaliseShareInfo`** — runs after every successful `ensureTapeUploaded`, regardless of view-only vs collab mode. Marks the tape as activated.
2. **`TapeCardView.checkAndCreateEmptyTapeIfNeeded`** — when an empty Collab tape receives its first clip. Marks the tape activated before inserting the next empty placeholder at the top.

## Gate sites

All four gates present the same `PaywallView` sheet — there's no tier-specific UI variant.

### 1. Share button (My Tapes, Collab tab — owner cards only)

- **Where:** `TapesListView.handleShare(_:)` and `CollabTapesView.handleShareIntent(for:)`.
- **Behaviour:** if the tape isn't yet in the activation set and the user is at the cap, show paywall instead of opening `ShareModalView`. Already-activated tapes always open the share sheet.
- **Visual:** the share button itself is unchanged — discovery happens at the moment of intent. Received tapes (`SharedTapesView`) hard-disable the share affordance, so no gate is needed there.

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
| `Tapes/Views/TapesListView.swift` | Hosts paywall sheet, gates share button on My Tapes. |
| `Tapes/Views/Share/CollabTapesView.swift` | Hosts paywall sheet, gates share button + empty collab placeholder taps via `TapeCardView.onActivationBlocked`. |
| `Tapes/Views/TapeCardView.swift` | Gates `FabSwipableIcon` (gallery/camera) and `handlePlaceholderTap` on empty collab tapes. Marks tape activated when first clip lands. |
| `Tapes/Views/Share/ShareLinkSection.swift` | Marks tape activated after every successful `ensureTapeUploaded`. |
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
