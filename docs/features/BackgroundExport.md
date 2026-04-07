# Background Export (BGContinuedProcessingTask)

Single-pass video export that continues in the background on iOS 26+ using Apple's `BGContinuedProcessingTask` API.

## Purpose & Scope

Allow users to start a tape export and leave the app while it completes. On iOS 26+, the system keeps the app process alive and shows a Live Activity with progress. On older iOS versions, the export pauses when the app is suspended and resumes when the user returns.

## Architecture

### Single-pass export (AVAssetReader/AVAssetWriter)

All exports — with or without blur background — use `TapeExportSession.runReaderWriter()`. The video composition (including `BlurredBackgroundCompositor` when blur is enabled) runs in-process through `AVAssetReaderVideoCompositionOutput`. Output is HEVC via `AVAssetWriter`.

### BGContinuedProcessingTask (iOS 26+)

- **Registration**: `ExportCoordinator.registerBackgroundExportHandler()` is called in `TapesApp.init()`.
- **Submission**: When the user taps export, `ExportCoordinator.exportTape()` submits a `BGContinuedProcessingTaskRequest` with `.fail` strategy (no queueing).
- **Progress**: The coordinator's polling timer updates `task.progress.completedUnitCount` and `task.updateTitle(_:subtitle:)` every 0.5 seconds.
- **Completion**: `task.setTaskCompleted(success:)` is called in `finishExport()`.
- **Expiration**: If the system cancels the task (resource pressure or user cancellation from Live Activity), the expiration handler cancels the export.
- **Notification**: A real local notification fires on actual completion (not ETA-based) when the app is backgrounded.

### Fallback (all iOS versions)

`UIApplication.beginBackgroundTask` is requested whenever the app enters the background during an active export. This provides approximately 30 seconds of execution time — enough for short exports and as a safety net if `BGContinuedProcessingTask` submission fails. On iOS 26+, the `BGContinuedProcessingTask` submit failure handler also triggers this fallback immediately.

## Key UI Components

- `ExportProgressDialog`: Single dialog with progress ring, ETA text, and "You can leave the app" messaging.
- `ExportCompletionDialog`: Success dialog with "Show in Photos" action.
- `ExportErrorAlert`: Standard alert for failures.
- Toolbar progress ring (shown when dialog is dismissed during active export).

## Data Flow

1. User taps export → `ExportCoordinator.exportTape()`
2. Coordinator submits `BGContinuedProcessingTaskRequest` (iOS 26+)
3. System calls registered handler → stores `BGContinuedProcessingTask` reference
4. `TapeExportSession.run()` builds composition, runs reader/writer pipeline
5. Progress polling updates UI and Live Activity
6. On completion: save to Photos → `setTaskCompleted(success:)` → notification (if backgrounded) → completion dialog

## Configuration

- **Info.plist** (at project root, outside the `Tapes/` synced group):
  - `BGTaskSchedulerPermittedIdentifiers`: `["StudioMorph.Tapes.export"]` (must be an array)
  - `UIBackgroundModes`: `["audio", "processing"]`
- **Build settings**: `INFOPLIST_FILE = Info.plist` (both Debug and Release)
- **Task identifier**: `StudioMorph.Tapes.export`

> **Note**: The `INFOPLIST_KEY_` build-setting mechanism does not reliably generate array-type Info.plist keys like `BGTaskSchedulerPermittedIdentifiers`. A physical Info.plist file is required for these keys. It must live outside the `Tapes/` directory (which uses `PBXFileSystemSynchronizedRootGroup`) to avoid "Multiple commands produce Info.plist" build errors.

## Testing / QA Considerations

- Test export with and without blur background enabled.
- Test leaving the app during export on iOS 26+ — verify Live Activity appears and export completes.
- Test leaving and returning on iOS < 26 — verify export resumes.
- Test cancellation from the in-app dialog and from the system Live Activity.
- Verify notification arrives when export completes in the background.
- Test with long tapes (10+ minutes) to verify progress reporting and system tolerance.
- Note: background GPU access is not available on iPhone; blur exports may be slower in the background due to CoreImage CPU fallback.
