# Tape Playback Pipeline – Current State

## Overview
- Unified `TapePlayerView` keeps a single `AVPlayer` instance alive and swaps items only at safe boundaries (pause, end-of-item, or deliberate seek) using `pendingComposition` state.
- `PlaybackPreparationCoordinator` streams partial compositions as clips resolve; each update reuses the existing player item when idle or queues the swap when playback is active.
- `TapeCompositionBuilder` now resolves assets via security-scoped URLs and falls back to cached local copies or Photos identifiers, eliminating mid-play flashes while handling revoked tmp files.
- UI state (`timeline`, `playbackIntent`, skip toast metrics) stays in sync across incremental updates, so progress, clip counts, and controls reflect the latest composition without disrupting playback.

## Operational Notes
- Warmup requests prepare the first five clips; subsequent clips append in place without interrupting playback.
- The cached asset path key combines `clip.id` and `clip.updatedAt`, so edits picking the same source produce a fresh readable copy automatically.
- FIG sandbox warnings (`err=-17507`) appear during asset probes and are expected as long as clips resolve successfully.
- Scrubbing or explicit seeks force-apply any queued composition before repositioning, guaranteeing consistent timeline metadata.

## Tech Debt Log
| ID | Area | Description | Status | Owner | Notes |
| --- | --- | --- | --- | --- | --- |
| TD-001 | Playback | Rapid skip tapping can land on a segment whose assets are still warming; the forced seek applies before the composition arrives and the player snaps back to the beginning. Add guardrails (debounce skip, block seeks until pending swap completes). | Open | Playback | Capture real-world repro steps; review once we plan polish pass. |

> _Add new entries below the table using the `TD-###` sequence so we can triage and bundle tech-debt fixes during polish._

