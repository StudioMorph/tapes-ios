# Carousel: UICollectionView Rewrite

## Summary

Replaced `SnappingHScroll` (raw `UIScrollView` + monolithic `UIHostingController`) with `SnappingCarouselView`, a `UICollectionView`-based component using `DiffableDataSource` and per-cell `UIHostingConfiguration`.

## Purpose & Scope

The original `SnappingHScroll` hosted **all** carousel items inside a single `UIHostingController` in an `HStack`. On every content change (clip insertion, duplication, deletion, thumbnail load, floating-clip lift/drop), it tore down and rebuilt the entire hosting view, then tried to restore the scroll offset via `DispatchQueue.main.async`. This caused:

- **Flash/reset to beginning** when duplicating a clip (especially to the left of the FAB).
- Fragile manual offset management that broke each time a new content-change path was added.

`SnappingCarouselView` eliminates these issues by leveraging `UICollectionView`'s native cell management.

## Key UI Components

| Component | Role |
|---|---|
| `SnappingCarouselView` | `UIViewRepresentable` wrapping `UICollectionView` |
| `UICollectionViewDiffableDataSource` | Efficient item diffing; insert/delete without full rebuild |
| `UIHostingConfiguration` | Embeds the existing `JiggleableClipView` per cell |
| `UICollectionViewFlowLayout` | Horizontal scroll, fixed item width, section insets for leading/trailing padding |

## Data Flow

1. `ClipCarousel` computes the `items: [CarouselItem]` array and a `contentVersion` hash.
2. `SnappingCarouselView.updateUIView` compares old vs new item IDs.
   - **IDs changed** (insert/delete/reorder): applies a new `DiffableDataSource` snapshot without animation, immediately positions at the correct snap index, then lets any pending programmatic scroll animate to the new FAB position.
   - **Version changed** (e.g. thumbnail loaded): reconfigures visible cells in-place via `snapshot.reconfigureItems`.
3. Snapping, gesture handling, and `onSnapped` callback logic are unchanged from the old `SnappingHScroll`.

## View Identity

**Critical**: `TapeCardView` must NOT use `.id()` modifiers that change with clip count on the carousel view. A changing `.id()` forces SwiftUI to destroy and recreate the `UIViewRepresentable`, calling `makeUIView` instead of `updateUIView`. This discards all coordinator state and causes position resets, animation loss, and alert presentation conflicts.

The carousel uses `.id("carousel-\(tape.id)")` (stable per tape) — this is correct. Any `.id()` that changes on insert/delete would defeat the DiffableDataSource architecture.

## View Update Safety

`UICollectionView` fires `scrollViewDidScroll` whenever its content offset changes — including during `updateUIView` and `onFirstLayout`. If the scroll callback modifies SwiftUI `@State` during these windows, it triggers "Modifying state during view update" warnings, which causes undefined behaviour (view recreation, lost coordinator state, multi-tape instability).

The `Coordinator.isUpdatingView` flag solves this:
- Set `true` at the start of `updateUIView` and `onFirstLayout`, `false` at the end (via `defer`).
- `scrollViewDidScroll` captures the correct fraction value but defers the state-modifying callbacks (`onScrollFractionChanged`, `reportPlusFrames`) to the next run loop via `DispatchQueue.main.async`.
- This ensures values are always correct (never stale) while state modifications happen strictly outside the view update cycle.

## Duplication Animation

When a clip is duplicated, `savedCarouselPosition` is NOT updated synchronously. This allows `currentSnapIndex` (used by `setPosition`) to remain at the old visual position, while `pendingTargetItemIndex` specifies the new position. The `performProgrammaticScroll` then animates smoothly from old to new. After the animation completes, `onSnapped` fires and updates `savedCarouselPosition`.

## Alert Presentation Safety

The "Delete Clip" action in jiggle mode goes through a two-step flow: a `confirmationDialog` (on the cell) followed by an `.alert` (on `TapeCardView`). Because both use UIKit presentation under the hood, the alert presentation is delayed by 350ms to allow the confirmation dialog to finish dismissing.

## Drop-Target Preferences

`StartPlusView` and `EndPlusView` previously set `DropTargetPreferenceKey` from inside the scroll content. Because each `UICollectionView` cell has its own SwiftUI tree, preferences no longer propagate up. Instead:

- The coordinator reports the global frames of the first (startPlus) and last (endPlus) cells via `onPlusFramesChanged`.
- `ClipCarousel` stores these in `@State` and sets the `DropTargetPreferenceKey` on its own body.
- The FAB drop target (set by `TapeCardView`) is unaffected.

## Testing / QA Considerations

- **Basic scroll & snap**: swipe left/right; FAB line stays centred on a gap.
- **Clip insertion** (camera, device, FAB): new clips appear, carousel scrolls so FAB ends up after the last inserted clip.
- **Duplication** (left & right of FAB): no reset/flash; smooth scroll to new FAB position.
- **Deletion**: position adjusts correctly; delete-all triggers tape-delete prompt.
- **Jiggle mode**: long press to enter, tap for options, long press to lift, drag to FAB, drop.
- **Lift/drop**: remaining clips close gap without jump; drop at start/end placeholders works.
- **Thumbnail loading**: cells update in-place without scroll disruption; batch imports should show all thumbnails within ~200ms of generation.

## Files Changed

| File | Change |
|---|---|
| `Tapes/Components/SnappingCarouselView.swift` | **New** – UICollectionView-based replacement |
| `Tapes/Components/ClipCarousel.swift` | Switched from `SnappingHScroll` to `SnappingCarouselView`; added drop-target frame bridge |
| `Tapes/Views/TapeCardView.swift` | Removed clip-count `.id()`; `fabOpacity` uses `scrollFraction`; deferred delete alert; duplication animation |
| `Tapes/Components/SnappingHScroll.swift` | Unchanged – retained for easy revert; no longer referenced |
