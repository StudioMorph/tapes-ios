# Background Download (BGContinuedProcessingTask)

Shared/collaborative tape downloads that continue in the background on iOS 26+ using Apple's `BGContinuedProcessingTask` API, with `beginBackgroundTask` fallback for older versions.

## Purpose & Scope

Allow users to start downloading a shared or collaborative tape and leave the app while it completes. On iOS 26+, the system keeps the app process alive and shows a Live Activity (Dynamic Island) with progress. On older iOS versions, a `UIApplication.beginBackgroundTask` provides approximately 30 seconds of additional execution. Completion haptics and a local notification fire when the download finishes in the background.

## Architecture

### BGContinuedProcessingTask (iOS 26+)

- **Registration**: `SharedTapeDownloadCoordinator.registerBackgroundDownloadHandler()` is called in `TapesApp.init()`.
- **Submission**: When `startDownload(shareId:api:tapeStore:)` is called, a `BGContinuedProcessingTaskRequest` is submitted with `.fail` strategy (no queueing).
- **Progress**: After each clip download, `updateContinuedTaskProgress()` updates `task.progress.completedUnitCount` and `task.updateTitle(_:subtitle:)` with an ETA or clip count.
- **Completion**: `task.setTaskCompleted(success:)` is called in `finishDownload(success:)`.
- **Expiration**: If the system cancels the task, the expiration handler falls back to `beginBackgroundTask`.
- **Notification**: A local notification fires on completion when the app is not active.

### Fallback (all iOS versions)

`UIApplication.beginBackgroundTask` is requested whenever the app enters the background during an active download (`handleScenePhaseChange`). This also serves as a fallback if `BGContinuedProcessingTask` submission fails.

## Key UI Components

- `SharedDownloadProgressOverlay`: Progress dialog with clip count and dismiss-to-toolbar support.
- Toolbar progress ring (shown in Shared/Collab tab when the progress dialog is dismissed).
- Download error alert for failures.

## Data Flow

1. User taps "Load tape" or sync badge → `SharedTapeDownloadCoordinator.startDownload()`
2. Coordinator submits `BGContinuedProcessingTaskRequest` (iOS 26+)
3. System calls registered handler → stores `BGContinuedProcessingTask` reference
4. Clips are downloaded sequentially from R2 and saved to Photos library
5. Progress updates the Dynamic Island Live Activity after each clip
6. On completion: merge into tape store → `setTaskCompleted(success:)` → haptics + notification (if backgrounded)

## Configuration

- **Info.plist**:
  - `BGTaskSchedulerPermittedIdentifiers`: includes `"StudioMorph.Tapes.download"`
  - `UIBackgroundModes`: `["audio", "processing"]`
- **Task identifier**: `StudioMorph.Tapes.download`

## Scene Phase Wiring

Both `SharedTapesView` and `CollabTapesView` observe `scenePhase` and forward changes to `downloadCoordinator.handleScenePhaseChange(_:)`, ensuring `beginBackgroundTask` is called when the app moves to background during an active download.

## Testing / QA Considerations

- Start downloading a shared tape, then leave the app — verify Dynamic Island appears on iOS 26+.
- Verify download completes in background and local notification fires.
- Return to the app after background completion — verify tape appears in the correct tab.
- Test cancellation from the in-app dialog during an active download.
- Test with tapes containing Live Photos to verify paired image/movie downloads complete.
- Test on iOS < 26 — verify `beginBackgroundTask` provides execution time.
