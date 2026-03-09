# Seam Transition Overrides

## Summary

Per-seam transition overrides allow users to set a custom transition style and duration for any individual boundary between two clips, overriding the tape-wide default.

## Purpose & Scope

Tapes previously supported only a single transition configuration per tape. This feature adds granular control so that each seam (boundary between two adjacent clips) can have its own transition type and duration. When no override exists for a seam, the tape's default settings apply.

## Key UI Components

- **FAB transition mode** — Swipe the FAB to the transition icon, then tap to open the seam transition sheet for the boundary the FAB is currently positioned on.
- **SeamTransitionView** (`Tapes/Views/SeamTransitionView.swift`) — A modal sheet presented from the FAB tap. Uses the same design patterns as `TapeSettingsView`: NavigationView → ScrollView → sections with `TransitionOption` rows and `TransitionDurationSlider`.
- **"Use Tape Default" button** — Allows the user to clear a seam override and revert to the tape-wide setting.
- **No transition at start/end** — When the FAB is at position 0 (before first clip) or N (after last clip), the transition tap does nothing as there is no boundary between two clips.

## Data Model

### `SeamTransition` (new struct in `Tape.swift`)
- `style: TransitionType` — The transition type for this seam.
- `duration: Double` — The transition duration for this seam.
- `key(leftClipID:rightClipID:)` — Generates a stable string key from the two adjacent clip UUIDs.

### `Tape` additions
- `seamTransitions: [String: SeamTransition]` — Dictionary of per-seam overrides keyed by `"leftClipID_rightClipID"`.
- `seamTransition(leftClipID:rightClipID:)` — Lookup helper.
- `setSeamTransition(_:leftClipID:rightClipID:)` — Set or clear an override.

Backward compatible: existing tapes without `seamTransitions` decode with an empty dictionary.

## Data Flow

1. User swipes FAB to transition mode and taps.
2. `TapeCardView` reads `savedCarouselPosition` to determine the seam (left clip at `pos-1`, right clip at `pos`).
3. `SeamTransitionView` is presented as a sheet with the two clip IDs.
4. On Save, the override is written to `tape.seamTransitions` and persisted via `TapesStore.updateTape`.
5. During playback, `TapeCompositionBuilder.buildTransitionDescriptors` checks for a seam override at each boundary before falling back to the tape default.

## Available Transition Styles (per seam)

- None
- Crossfade
- Slide L→R
- Slide R→L

Note: "Randomise" is excluded from per-seam options as it is a tape-level concept.

## Testing / QA Considerations

- Verify seam overrides persist after app restart.
- Verify overrides survive clip reordering (keys are based on clip UUIDs, so moving clips changes the boundary key — this is intentional as the seam between those two clips no longer exists).
- Verify playback correctly applies per-seam overrides alongside tape defaults.
- Verify "Use Tape Default" clears the override and playback reverts.
- Verify the FAB does nothing at position 0 and N (no seam to configure).
- Verify backward compatibility with tapes saved before this feature.
