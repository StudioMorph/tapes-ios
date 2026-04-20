# Large File Extraction

**Status:** draft, awaiting approval. **Deferred** — post-launch refactor.
**Scope:** iOS only. Three files split into smaller ones.
**Risk:** medium. Extracting from files this central is inherently risky; bugs creep in during reshuffling.
**Deploy posture:** each extraction is its own PR. Don't batch them.

---

## Problem

Three files have grown large enough that reading them cover to cover is hard, and changes to them are riskier than they should be:

| File | Size |
|---|---|
| [TapeCompositionBuilder.swift](../../Tapes/Playback/TapeCompositionBuilder.swift) | ~25,000 tokens, ~1,200+ lines |
| [TapePlayerViewModel.swift](../../Tapes/Views/Player/TapePlayerViewModel.swift) | ~1,310 lines |
| [TapesStore.swift](../../Tapes/ViewModels/TapesStore.swift) | ~1,400 lines |

None are broken. All are well-structured. But each is approaching the size where a bug can hide in a corner no one looks at.

---

## Why defer

Splitting any of these is a multi-commit refactor that touches lots of call sites. Doing it during launch prep competes with launch work. Bugs introduced during the split will likely only surface on device.

Schedule: after the pre-release list is done, before the first big feature-work cycle post-launch. Ideally while the codebase is otherwise stable so the refactor is the only change in flight.

---

## Proposed extractions

### `TapeCompositionBuilder.swift`

Already has two extension files: `+AssetResolution.swift` and `+ImageEncoding.swift`. Good start. More to split:

- **`TapeCompositionBuilder+Transitions.swift`** — `buildTransitionDescriptors`, the `MotionEffect` types, seam-override resolution. ~200 lines.
- **`TapeCompositionBuilder+VideoInstructions.swift`** — `buildVideoInstructions`, `buildBlurVideoInstructions`, all the per-frame compositor orchestration. ~300 lines.
- **`TapeCompositionBuilder+Audio.swift`** — the audio-mix parameter construction, volume ramps for crossfades, Live Photo muting. ~100 lines.
- **`TapeCompositionBuilder+TimingAsset.swift`** — `timingAsset`, `buildTimingAsset`. The 2x2 dummy H.264 for still images. ~80 lines.

The core file remains with the timeline assembly, the `buildPlayerItem` / `buildExportComposition` entry points, the nested types (`Segment`, `Timeline`, `PlayerComposition`, etc.), and asset-loading orchestration. Probably ~400 lines.

### `TapePlayerViewModel.swift`

Harder to split because it's a single `ObservableObject` with a lot of coupled state. Two approaches:

**Approach A: extract helpers into extension files.** Keep one class, split it across several files.
- `TapePlayerViewModel+Preload.swift` — `startSequentialPreload`, `loadClipComposition`, cache management.
- `TapePlayerViewModel+Transition.swift` — `startTransition`, `finalizeTransition`, `cancelTransition`, ramp logic.
- `TapePlayerViewModel+Drag.swift` — interactive drag gesture handlers.
- `TapePlayerViewModel+AirPlay.swift` — AirPlay pre-rendering.
- `TapePlayerViewModel+Observers.swift` — installObservers, removeObservers, system-event handling.

Pros: pure split, no architectural change. Cons: still one class, still 1300 lines of logic, just spread across files.

**Approach B: extract collaborators into smaller classes.** E.g. a `PlayerPreloadEngine`, a `PlayerTransitionController`, a `PlayerDragController`. Each owns a subset of state.

Pros: real decomposition, each part independently testable. Cons: bigger refactor, tricky because the state is currently entangled (transition observes cache, drag triggers transition, etc.).

Recommendation: **Approach A** for the first pass. If it still feels unwieldy after, do Approach B.

### `TapesStore.swift`

Already has subsystems embedded (floating clip state, album association queue, metadata queue, persistence actor). Some of these could move out:

- **`FloatingClipController.swift`** — `liftClip`, `dropFloatingClip`, `returnFloatingClip`, the `@Published` drag state. ~100 lines. Can be a separate `ObservableObject` or a `@Published` struct.
- **`TapeAlbumCoordinator.swift`** — `associateClipsWithAlbum`, `handleAlbumRenameIfNeeded`, `scheduleAlbumDeletionIfNeeded`, the album association queue. ~200 lines.
- **`ClipMetadataCoordinator.swift`** — `generateThumbAndDuration`, `enqueueMetadataWork`, `drainMetadataQueue`, the concurrency limit. ~200 lines.
- **`TapeEmptyInvariant.swift`** — empty tape and empty collab tape restoration logic. Small, ~50 lines, might not justify its own file.

Core `TapesStore` keeps: tape CRUD, persistence, published tape list, computed properties. Down to ~800 lines.

---

## General principles for the extraction

- **No behaviour changes.** Every extraction is pure move. If during the move I see a bug or improvement, I *note it* and fix it in a separate commit afterwards. Mixing refactor and fix is how regressions ship unnoticed.
- **One file extracted per commit.** Small commits, each independently revertable.
- **Test before and after.** Run the app through the full smoke test. Same behaviour expected.
- **Previews keep working.** SwiftUI previews don't care how the code is split, but some preview setups reference private helpers — audit during the extraction.

---

## Risks

- **Subtle cross-file access changes.** A `private func` becomes `internal`-implicitly when moved to an extension in another file (same module). Unless marked `fileprivate`. Audit.
- **Memory-management footprint of splitting into separate classes.** Weak refs between collaborators. If we accidentally create a retain cycle, the `ObservableObject` leaks and the player never deallocates. Easy to catch with Instruments, but easier to prevent with review.
- **State transitions that span methods now living in different files.** The player VM's transition state especially. Keep related methods together; if a split would separate them by more than a jump, don't split there.

---

## Verification

For each extraction:

1. Extract. Commit locally. Build, run.
2. Full smoke test (create, edit, export, share, play, receive). Two devices.
3. Xcode's Instruments — memory leaks pass. No new leaks.
4. Commit to main.

Repeat for next extraction.

---

## Deploy

iOS-only, each extraction ships with its build.

---

## Open questions

- Approach A or B for `TapePlayerViewModel`? Recommend A first.
- Should we write tests *before* the extraction or after? Before is better (pins behaviour). But tests on these files are hard to write. Pragmatic answer: write tests for the pieces that will be extracted (preload, transition math) before, as part of [TestCoverageBaseline.md](TestCoverageBaseline.md), then use those tests to verify the extraction didn't regress.
