# Free-Tier Paywall Gates — Implementation Plan

## Summary

Wire the new `PaywallView` into the four free-tier gates we agreed:

1. **Share / Collab cap** — 5 tapes lifetime, combined.
2. **AI Prompt tab** — Plus-only.
3. **12K Library** — 1,000 tracks for Free, with an upgrade footer toolbar.
4. **(Out of scope, follow-up pass)** — watermark on export, ad-free playback.

All gates are presented through the same `PaywallView` sheet. No tier-specific UI variants; only access points differ.

---

## 1. Counter — single source of truth in `EntitlementManager`

**Why here:** all gate-checks already reach into `entitlementManager`, and the count is global, not per-tape. Avoids spreading UserDefaults reads across views.

### Storage

UserDefaults, scoped to install. Reinstall = reset. Server-side later when we have proper accounts.

```text
Key:   "monetisation.activatedTapeIDs.v1"
Value: [String] — UUID strings of tapes that have been counted
```

We persist the **set of activated tape IDs**, not just the count, so:

- The same tape can't double-count if it's both shared *and* turned into a collab.
- Re-tapping share on an already-counted tape doesn't trigger the gate.
- Existing shared/collab tapes on Jose's and Isabel's devices get migrated by being inserted into the set on first launch (see §6).

### New API on `EntitlementManager`

```swift
// MARK: - Free-tier limits (public read)
static let freeShareCollabCap: Int = 5
static let freeLibraryTrackCap: Int = 1000

private(set) var activatedTapeIDs: Set<UUID>     // loaded from UserDefaults
var activatedTapeCount: Int { activatedTapeIDs.count }

// Gate queries
func canActivateNewTape() -> Bool                // count < 5
func isTapeAlreadyActivated(_ id: UUID) -> Bool

// Mutation (called from the activation success paths in §3)
func markTapeActivated(_ id: UUID)               // adds to set + persists

// Feature gates
var canUseAIPrompt: Bool { isPremium }
var libraryTrackCap: Int? { isPremium ? nil : Self.freeLibraryTrackCap }
```

`activatedTapeIDs` is `@Published` so views can react if needed (badge counts in Account, etc.).

### Plus → cap removed automatically

When `accessLevel` flips to `.plus`, the gate queries return `true` regardless of the activation count. We don't clear the set — if the user ever downgrades back to free, the same tapes stay grandfathered.

---

## 2. Paywall presentation pattern

A single `@State private var showingPaywall = false` per host view, plus a `.sheet(isPresented: $showingPaywall) { PaywallView() }` attachment. The host views that need it:

- `TapesListView` — for the share-button gate on My Tapes
- `CollabTapesView` — for the share-button gate and collab-creation gate
- `SharedTapesView` — for the share-button gate on received tapes (rare; mostly read-only there, but the share affordance exists for owner's view-only tapes)
- `BackgroundMusicSheet` — for the AI Prompt segment gate
- `LibraryBrowserView` — for the "Upgrade to unlock 12,000 tracks" footer

`AccountTabView` already presents `PaywallView` via the upgrade row — no change needed there.

---

## 3. Gate 1 — Share / Collab cap (5 lifetime, combined)

### Counter increment points

We increment **once per tape**, on the moment that tape becomes externally accessible. Two paths:

**Path A — Share success on a previously-unshared, non-collab tape.**
Today, `ShareLinkSection` calls `ensureTapeUploaded(intendedForCollaboration:)` via `ShareUploadCoordinator`. On the success callback (where `shareInfo` gets written to the tape), we add the tape ID to `activatedTapeIDs`.

**Path B — Collab tape commits its first clip.**
In `TapeCardView.checkAndCreateEmptyTapeIfNeeded()` — already runs when `tape.clips.count > 0 && !tape.hasReceivedFirstContent`. If `tape.isCollabTape`, increment.

Both paths are idempotent — the set check makes a no-op if the tape was already counted.

### Gate site A: Share button on the card

Currently in `TapeCardView`:

```235:235:Tapes/Views/TapeCardView.swift
.onTapGesture { guard !isShareIconDisabled, !isJiggling else { return }; stopPreviewIfNeeded(); onShare() }
```

The `onShare` closure resolves to `tapeToShare = tape` in the host view. Insert the gate **at the host site**, not inside `TapeCardView` — that way `TapeCardView` stays presentation-pure. Pattern (in `TapesListView`):

```swift
private func handleShare(_ tape: Tape) {
    let alreadyActivated = entitlementManager.isTapeAlreadyActivated(tape.id)
    let hasCapacity = entitlementManager.canActivateNewTape()
    if !alreadyActivated && !hasCapacity {
        showingPaywall = true
        return
    }
    tapeToShare = tape
}
```

Same shape in `CollabTapesView.onShare:` and `SharedTapesView.onShare:`.

The share button itself stays visually unchanged (per A in our prior decision). Discovery of the limit happens at the moment of intent.

### Gate site B: Empty Collab tape — Media picker / Camera tap

The `FabSwipableIcon` action and `handlePlaceholderTap(_:)` in `TapeCardView` are the entry points that lead to creating clips on an empty tape. We gate **only** when:

- `tape.isCollabTape == true`
- `tape.clips.isEmpty && !tape.hasReceivedFirstContent` (i.e. truly empty placeholder)
- `entitlementManager.canActivateNewTape() == false`

For non-collab empty tapes (My Tapes), we **don't** gate — adding clips to a personal tape doesn't count toward the cap.

This needs `TapeCardView` to receive an `onActivationBlocked: () -> Void` callback (set by the host to flip its `showingPaywall`). We wrap the existing `FabSwipableIcon` `case .gallery:` / `case .camera:` blocks and `handlePlaceholderTap(_:)` body with the gate check at the top:

```swift
if tape.isCollabTape, isEmptyTape, !entitlementManager.canActivateNewTape() {
    onActivationBlocked()
    return
}
// ...existing code...
```

`onActivationBlocked` flows up to `CollabTapesView`, which sets `showingPaywall = true`.

### Gate site C: Email recipient on the share sheet

In `ShareLinkSection`, the recipient flow eventually triggers the same `ensureTapeUploaded(intendedForCollaboration:)` call — we don't need a second gate here, because the share button that opens the sheet is already gated. **Decision: gate only at the entry point to the sheet, not inside it.** Keeps the sheet a single responsibility (configure & invite) and avoids stacking modals.

> If you want belt-and-braces (paywall *also* on tap of the recipient submit button inside the sheet), say so and I'll add it.

---

## 4. Gate 2 — AI Prompt tab (Plus only)

In `BackgroundMusicSheet.MusicBarModifier.picker`, the segmented control currently binds to `selectedTab` directly. Free-tier behaviour: tapping the AI Prompt segment shows the paywall and **does not** change the segment.

Implementation: replace the direct `Picker` binding with an intermediary that intercepts `.aiPrompt`:

```swift
private var pickerBinding: Binding<BackgroundMusicSheet.Tab> {
    Binding(
        get: { selectedTab },
        set: { newValue in
            if newValue == .aiPrompt && !entitlementManager.canUseAIPrompt {
                showingPaywall = true   // hosted on BackgroundMusicSheet
                return                  // selectedTab unchanged
            }
            selectedTab = newValue
        }
    )
}
```

Segment visibly snaps back to its previous position because the binding setter rejects the change. Apple-native; no animation glitches.

---

## 5. Gate 3 — 12K Library cap (1,000 tracks for Free)

**Important honesty note:** I told you previously that this was implemented. It isn't. We discussed the design ("Upgrade to unlock 12,000 tracks" footer) but nothing was written. This plan covers it from scratch.

### Cap behaviour

The cap applies to the **full unfiltered library**. Free users get the first 1,000 tracks Mubert returns (sorted by Mubert's default order). Filters then operate on whatever subset of those 1,000 match.

Why the unfiltered set: tells the user honestly "you have access to 1,000 of 12,000 tracks". If we capped post-filter, a Free user could change a filter and see different tracks magically appear, which is misleading.

### Where the cap is enforced

In `LibraryBrowserViewModel.loadTracks(api:reset:)`:

- Pass `entitlementManager.libraryTrackCap` into the load function.
- Stop pagination once the cumulative loaded-track count reaches the cap.
- The next-page trigger checks `loadedCount < cap` before requesting more.

### Filter counts

`tracksCount` per filter value comes from Mubert. For Free users we display the **uncapped** server count (so they see "Lo-fi (248)") because that's the truth about the library. The cap only affects which tracks appear in the list. This avoids two layers of ambiguity.

### Bottom upgrade toolbar (Free only)

A `safeAreaBar(edge: .bottom)` on `LibraryBrowserView` containing:

```
[ Upgrade to unlock 12,000 tracks → ]
```

A bordered prominent button with a chevron-right icon, taps to flip `showingPaywall` on the parent `BackgroundMusicSheet`. The toolbar is hidden when `entitlementManager.isPremium`.

The bar uses the same `safeAreaBar` modifier pattern we already use for the top filter bar — keeps the sheet consistent.

---

## 6. Migration — grandfather existing shared / collab tapes

On first launch after this change ships, `EntitlementManager.init` walks `tapesStore.tapes` once and seeds `activatedTapeIDs` with every tape where `tape.isShared || tape.isCollabTape`. This ensures Jose and Isabel (who both have ≫5 active tapes from testing) start at their real count, not zero, and existing tapes stay grandfathered.

Trigger: a one-shot UserDefaults flag `monetisation.didMigrateActivatedTapeIDs.v1`. Once set, we don't re-walk on subsequent launches.

Edge case: `EntitlementManager` doesn't currently have a reference to `TapesStore`. We can either:

- (A) Pass `TapesStore` into `EntitlementManager.init` (clean DI, slightly more refactor).
- (B) Run the migration from `TapesApp.init` after both stores exist.

**Recommend B** — single startup-orchestration site, no new coupling on `EntitlementManager`. The migration call is a one-liner: `entitlementManager.migrateActivatedTapeIDs(from: tapesStore.tapes)`.

---

## 7. Out of scope (logged for follow-up)

These are listed in the paywall feature copy but are deliberately **not** in this pass:

- **No watermark on export** — touches the export composition pipeline (`AVMutableComposition` / `AVAssetExportSession`). Will plan separately when we look at export overhaul.
- **No ads** — already wired to `entitlementManager.isPremium` in `TapePlayerViewModel.isFreeUser` (line 162). Behaviour is correct today; no work needed in this pass.
- **Server-side persistence of the activation count** — UserDefaults for now; revisit when accounts can carry monetisation state.

Add to `docs/BACKLOG.md` after this plan is approved.

---

## 8. Test plan

Manual verification on device, free tier (sign out of any active sandbox subscription first):

1. **Share cap counts up correctly.** Share 5 distinct My Tapes with view-only links → 6th share-button tap → paywall.
2. **Same tape doesn't double-count.** Share a single tape twice → counter still 1.
3. **Collab counts toward the same 5.** Activate 3 view-only shares + 2 collab tapes (5 total) → next share *or* next collab placeholder tap → paywall.
4. **Already-active tapes grandfathered.** With the migration in place, existing shared tapes still open their share sheet without paywall, even if the count is over 5.
5. **AI Prompt gate.** Open Background Music sheet → tap AI Prompt segment → paywall opens, segment stays on Library.
6. **Library cap.** Scroll to the end of the library → exactly 1,000 tracks → bottom upgrade toolbar visible → tap → paywall.
7. **Plus tier.** Subscribe via sandbox → all four gates disappear: share works, collab works, AI Prompt segment works, library scrolls past 1,000, bottom toolbar gone.
8. **Restore.** Cancel sandbox subscription → relaunch → gates return; activation set persists; user is at whatever count they reached.

Sandbox cleanup: deleting the app between tier flips clears UserDefaults, including the activation set — useful to reset the count for testing.

---

## 9. File touch list (estimated)

- `Tapes/Core/Subscription/EntitlementManager.swift` — counter, gates, migration helper.
- `Tapes/TapesApp.swift` — call migration on launch.
- `Tapes/Views/TapesListView.swift` — share gate, paywall sheet.
- `Tapes/Views/Share/CollabTapesView.swift` — share gate, paywall sheet, plumb `onActivationBlocked` to `TapeCardView`.
- `Tapes/Views/Share/SharedTapesView.swift` — share gate, paywall sheet.
- `Tapes/Views/TapeCardView.swift` — `onActivationBlocked` callback, gates around `FabSwipableIcon` actions and `handlePlaceholderTap`.
- `Tapes/Core/Networking/ShareUploadCoordinator.swift` *or* the call-site that finalises share success — call `markTapeActivated`.
- `Tapes/Views/BackgroundMusicSheet.swift` — AI Prompt gate via picker binding interception, hosts the paywall sheet for both AI and Library gates.
- `Tapes/Views/LibraryBrowserView.swift` — apply cap in pagination, bottom upgrade toolbar.
- `Tapes/ViewModels/LibraryBrowserViewModel.swift` (if it exists separately) — accept cap parameter.
- `docs/features/SubscriptionTiers.md` (new) — document Free vs Plus matrix.
- `docs/BACKLOG.md` — log watermark + ads + server-side persistence.

No backend changes. No model changes (`Tape` already has `isShared` / `isCollabTape`).

---

## 10. Open questions before I implement

None remaining; everything in §1 confirmed in our last exchange. Final go from you and I write the code.
