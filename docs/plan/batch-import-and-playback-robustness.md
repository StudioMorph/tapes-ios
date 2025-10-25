# iOS Batch Import UX & Playback Robustness Plan

## A. Architecture & State Design

### Clip Timeline State Machine
- `placeholder` → spawned immediately when multi-select returns; carries target insertion index and lightweight metadata (asset type, provisional duration guess).
- `loading.queued` → placeholder enqueued with the import pipeline but no work has started; UI shows spinner with queued badge.
- `loading.downloading` → actively fetching underlying data (PHPicker transfer, iCloud, sandbox copy). Expose progress if provider delivers it; otherwise animate indeterminate spinner.
- `loading.transcoding` → local processing phase (image → video synthesis, metadata extraction, thumbnail generation). Use deterministic order; display “Processing…” glyph.
- `ready` → clip resolved with `Clip` payload (duration, thumbnail, URLs) and replaces the placeholder in the tape.
- `error` → pipeline failed; retain placeholder footprint with failure badge + retry button (keeps slot stable, avoids reflow). Errors record reason for telemetry.
- Sub-states: `loading.iCloud` (assets flagged `PHAssetSourceType.typeCloudShared` or network fetch) for alternate messaging; `loading.thumbnailPending` when clip is ready but thumbnail still rendering.

### Progress Model
- Per-item: track `progress` (0…1) plus `phase` enum above. Persist transient state in a new `ClipLoadingState` dictionary keyed by placeholder ID inside `TapesStore`.
- Aggregate: compute fraction of placeholders resolved (`ready` / total) and best-effort weighted progress (downloads weight higher). Surface aggregate progress in UI banner (e.g., “Importing 8 clips… 3 ready”).
- UI messaging: replace silent gap with inline placeholders showing activity; optional transient toast when batch begins (“Importing 12 items…”).

### Playback Readiness Model
- Introduce `PlaybackPreparationState` maintained by a coordinator:
  - `idle`, `preparing`, `ready(minimumSegments:Int)`, `partialReady(segmentsPrepared:Int, waiting:Int)`, `error`.
  - Minimum readiness guarantee: first contiguous block of clips covering ≥6 seconds or first 2 clips (whichever larger) fully prepared before autoplay.
  - Progressive start: begin playback when guarantee met; continue preparing remaining segments in background queue. Update player timeline as more segments finalize.
  - Handle gaps: if upcoming segment misses deadline, pause with inline toast (“Clip 5 still loading”) and offer skip.

## B. Concurrency & Performance Strategy

### Pipeline Batching & Limits
- Asset acquisition (PHPicker transfers, iCloud fetches):
  - Use bounded `AsyncSemaphore` (e.g., max 3 concurrent transfers) to avoid saturating IO.
  - Separate lane for local sandbox URLs vs. remote iCloud assets; prioritize local first for quick wins.
- Thumbnail generation & metadata:
  - Offload to background queue with max 2 concurrent `AVAssetImageGenerator` jobs; reuse shared generator cache.
  - Release interim `UIImage` buffers once JPEG stored in `Clip`.
- Image-to-video synthesis:
  - Serial per-core queue (max 1–2 concurrent writers) to keep memory stable; reuse pixel buffers when possible.
- Composition assembly for playback:
  - Build per-segment `AVMutableComposition` fragments in background queue with concurrency capped at 2; merge into master timeline incrementally.
  - Maintain small sliding window of prepared segments (e.g., next 3 clips) to limit memory footprint.

### Back-pressure & Cancellation
- Import queue holds `ImportTask` objects; when user leaves tape or cancels, cancel pending tasks and mark placeholders as aborted.
- Apply timeouts (e.g., 15 s for iCloud download, 20 s for transcoding). On timeout, mark clip `error` with retry affordance.
- Free disk/memory: delete temporary MOV files once merged; call `autoreleasepool` inside heavy loops.

## C. UX Flow & Non-Regression Notes

- Immediate placeholders: upon picker dismissal, insert ordered placeholders into tape via `TapesStore` before any heavy work, respecting the target insertion index and carousel animation rules.
- Per-item reveal: as each placeholder reaches `ready`, swap it with actual `Clip`, trigger carousel refresh, and animate thumbnail fade-in. Keep others spinning.
- Play button: if tapped during import, show progress overlay (“Preparing 2 of 10”). Start playback once readiness threshold met; continue streaming further clips. Provide skip fallback if a later clip stalls.
- Non-regression checklist:
  - Preserve carousel snapping, FAB gestures, start/end plus placeholders.
  - Ensure first-content logic still inserts new empty tape.
  - Maintain existing thumbnail caching, Ken Burns transitions, transition settings, export and AirPlay paths.
  - Keep existing long-press delete and edit gestures unaffected.

## D. Failure Modes & Recovery

- Per-item error UI: badge placeholder with warning icon + “Retry” pill; tapping retries from last failed phase. Provide `More Info` sheet surfaced from aggregated error log.
- Partial failure: do not block other clips; continue with successful ones. Playback skips errored segments with toast (“Skipped Clip 7 – download failed”).
- Limited Photos access: detect `.limited` auth; if asset needs expanded access, show inline CTA pointing to Settings; keep placeholders visible.
- iCloud offline: transition to `error` with “Waiting for download” message but keep retrying in background with exponential backoff; allow user to continue playback with ready segments.

## E. File Inventory & Integration Points

- **Models**
  - `Tapes/Models/Clip.swift`: introduce optional `loadingState` or companion struct; ensure Codable compatibility by storing in auxiliary map in `TapesStore` to avoid migration churn.
  - `Tapes/ViewModels/TapesStore.swift`: manage placeholder insertion, loading state map, aggregate progress, cancellation logic.
- **Import**
  - `Tapes/Features/MediaPicker/MediaPickerSheet.swift` & `MediaProviderLoader.swift`: emit lightweight descriptors immediately; queue heavy resolution tasks via new `ImportQueue`.
  - `Tapes/Features/Import/PhotoImportCoordinator.swift`: align APIs and share queue.
  - New `Tapes/Features/Import/ImportPipeline.swift`: encapsulate bounded async queues, progress reporting, cancellation.
- **UI**
  - `Tapes/Components/ClipCarousel.swift` & `ThumbnailView.swift`: render placeholder states, progress, retry UI.
  - `Tapes/Views/TapeCardView.swift`: wire placeholder creation, listen to store progress, keep first-content behaviour intact.
  - Optional banner component for aggregate progress.
- **Playback**
  - New `Tapes/Playback/PlaybackPreparationCoordinator.swift`: orchestrate incremental composition building using `TapeCompositionBuilder`.
  - `Tapes/Views/Player/TapePlayerView.swift`: observe coordinator state, update spinner/progress, handle partial readiness & skips.
  - `Tapes/Playback/TapeCompositionBuilder.swift`: expose segment-by-segment API and support cancellation hooks.
- **Telemetry**
  - Extend `Tapes/Platform/Photos/TapesLog.swift` categories (e.g., `importQueue`, `playbackPrep`) for structured logs.
- **Testing**
  - Add pipeline unit tests under `TapesTests/ImportPipelineTests.swift` and playback coordinator tests.

## F. Performance Budgets & Telemetry

- Budgets:
  - Placeholder render: <150 ms from picker dismissal to first placeholder visible.
  - Per-clip availability: first clip ready <1 s for local assets, <3 s for iCloud.
  - Playback start after large import (20 clips mixed photo/video): <4 s to autoplay.
  - Memory ceiling during preparation: <350 MB on A12-class devices.
  - Composition rebuild jitter: keep main-thread blocking under 5 ms per update.
- Telemetry:
  - Log durations for each pipeline phase, queue depth, time-to-first-play, skipped clip count.
  - Record memory snapshots (using `os_signpost`) during heavy phases.
- Manual test matrix:
  - Small (3 clips), medium (10 clips), large (30 clips) imports.
  - Mix of local videos/photos, HEIC/JPEG, 4K assets.
  - iCloud-only assets (download needed) + offline scenario.
  - Devices: iPhone SE (A13), iPhone 14, iPad Pro; run in foreground/background transitions.

## G. Rollout, Guardrails, Fallbacks

- Feature flag `FeatureFlags.importPipelineV2` to gate new placeholders + queue; fallback to legacy flow if disabled.
- Separate flag `FeatureFlags.incrementalPlaybackPrep` for staged rollout of progressive playback.
- Rollback: toggling flags reverts to prior synchronous behaviour without data migration; ensure tests guard both paths.
- Migration: existing tapes unaffected—placeholders are transient; ensure store clears orphan states on launch.

## H. Acceptance Criteria

- Placeholders appear instantly after multi-select, aligned with end-user insertion order.
- UI remains responsive; carousel scroll and FAB interactions stay fluid during background processing.
- Play button never spins indefinitely; playback starts within budget and continues even while remaining clips prepare.
- No crashes or OOM observed under large imports; pipeline logs show bounded concurrency.
- Existing gestures, settings, export, AirPlay, and carousel behaviour remain unchanged.
- Errors surface per clip without blocking overall workflow; retry succeeds when network returns.

## Implementation Roadmap & Task Breakdown

### Phase 0 – Baseline & Guardrails
- Profile current large-import and playback flows (time-to-placeholder, queue depth, memory). Capture logs to validate future metrics.
- Wire up feature flags (`importPipelineV2`, `incrementalPlaybackPrep`) and stub telemetry endpoints in `TapesLog`.
- Draft QA playbook covering the manual matrix in section F; align on success thresholds with product/design.

### Phase 1 – Placeholder & State Infrastructure
- Extend `Clip`/`TapesStore` with placeholder + loading state models; persist transient state in store map and expose Combine publishers for UI.
- Update carousel/thumbnail components to render placeholders, progress, error badges, and retry affordance while preserving gestures.
- Emit placeholder entries the moment picker returns; ensure first-content tape creation still fires exactly once.

### Phase 2 – Bounded Import Pipeline
- Introduce `ImportPipeline` service with staged queues (download, metadata, thumbnail, synthesis) and bounded concurrency + cancellation semantics.
- Refactor media picker, camera, and PHPicker coordinators to enqueue work via the pipeline and feed progress updates back to the store.
- Implement retry/timeout handling, back-pressure (queue size caps), and cleanup of temporary files to hit memory budgets.

### Phase 3 – Progressive Playback Preparation
- Add `PlaybackPreparationCoordinator` to orchestrate incremental segment preparation using `TapeCompositionBuilder`, respecting per-stage limits.
- Enhance composition builder with cancellable, per-segment APIs and support for streaming timelines into `AVPlayerItem`.
- Update `TapePlayerView` to observe preparation state, manage the “Preparing” overlay, handle progressive play/skip, and surface errors gracefully.

### Phase 4 – Telemetry, Testing, and Polish
- Instrument pipeline phases and playback readiness with os_signposts/log events; verify metrics hit target budgets across the device matrix.
- Author unit/integration tests for placeholder lifecycle, import queue sequencing, cancellation, and playback coordinator fallback paths.
- Run QA sweeps (small/medium/large imports, iCloud on/off, background) with flags enabled; address regressions before default rollout.

### Phase 5 – Rollout & Monitoring
- Ship behind flags for internal dogfood; monitor logs/metrics for queue depth, time-to-first-play, error rates.
- Iterate on tuning parameters (concurrency caps, readiness thresholds) based on telemetry.
- Prepare rollback/fallback checklist and release notes before enabling flags for all users.
