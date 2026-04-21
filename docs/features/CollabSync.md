# Unified Collab Sync (CollabSyncCoordinator)

Single unified sync experience for collaborative tapes that need both uploads and downloads.

## Purpose & Scope

When a collaborative tape has both local unsynced clips (to upload) and remote new clips (to download), the user previously saw two sequential dialogs. `CollabSyncCoordinator` orchestrates both operations as a single continuous flow, presenting one "Syncing…" dialog from start to finish.

## Architecture

### Composition, not duplication

`CollabSyncCoordinator` does **not** reimplement upload or download logic. Instead, it **composes** the existing `ShareUploadCoordinator` and `SharedTapeDownloadCoordinator`:

1. Sets `isManagedBySync = true` on both coordinators, which suppresses their individual dialog flags, completion feedback, and `BGContinuedProcessingTask` submission.
2. Calls their existing public methods (`ensureTapeUploaded`, `contributeClips`, `startDownload`) — all logic stays in one place.
3. Observes their `@Published` state via Combine to aggregate progress and detect phase completion.
4. Manages its own unified `BGContinuedProcessingTask` for the Dynamic Island.
5. Clears `isManagedBySync = false` when the sync finishes.

### When it activates

`CollabSyncCoordinator` is used **only** when a collab tape has both uploads **and** downloads pending. If only one direction is needed, the existing coordinators handle it independently with their own dialogs.

### Phase sequencing

1. **Upload phase**: The sync coordinator calls the upload coordinator's existing method. It observes `$isUploading` via Combine — when it drops to `false`, the upload is complete.
2. **Download phase**: If uploads succeeded, the sync coordinator starts the download coordinator. It observes `$isDownloading` via Combine — when it drops to `false`, the download is complete.
3. Both coordinators' `objectWillChange` publishers are observed to reactively aggregate progress counts.

### The `isManagedBySync` flag

Both `ShareUploadCoordinator` and `SharedTapeDownloadCoordinator` have a public `isManagedBySync` property. When `true`:

- `showProgressDialog` is not set
- `showCompletionDialog` is not set
- Completion haptics and local notifications are skipped
- `BGContinuedProcessingTask` submission is skipped (the sync coordinator owns it)
- All actual work (uploading, downloading, state updates, callbacks) proceeds normally

## Key UI Components

- `CollabSyncProgressDialog`: "Syncing…" title, sync icon, aggregated progress count, ETA, and "You can leave the app" messaging.
- `CollabSyncCompletionDialog`: "Tape Synced" with green checkmark.
- `CollabSyncErrorAlert`: "Sync Failed" with error details.
- Toolbar sync icon: appears when the progress dialog is dismissed mid-sync.

## Background Support

- `BGContinuedProcessingTask` (iOS 26+) with Dynamic Island showing "Syncing Tape" — managed by the sync coordinator, not by individual coordinators during sync.
- `beginBackgroundTask` fallback ensures continuous execution across phase transitions.
- Local notification on completion when the app is backgrounded.

## Configuration

- **Info.plist**: `BGTaskSchedulerPermittedIdentifiers` includes `"StudioMorph.Tapes.collabSync"`.
- **Task identifier**: `StudioMorph.Tapes.collabSync`

## Data Flow

1. User taps sync badge on a collab tape with both pending uploads and downloads
2. `CollabTapesView.handleSync` detects both directions → calls `syncCoordinator.startSync()` passing references to both coordinators
3. Sync coordinator sets `isManagedBySync = true`, starts upload via existing coordinator
4. Combine observer detects upload completion → starts download via existing coordinator
5. Combine observer detects download completion → plays feedback, shows unified completion dialog
6. `isManagedBySync = false` restored on both coordinators

## Testing / QA Considerations

- Create a collab tape, add clips locally, and have another user add clips remotely. Tap the sync badge — verify one "Syncing…" dialog covers the entire operation.
- Verify progress counter increments continuously across both phases.
- Dismiss the dialog mid-sync — verify the toolbar icon appears and tapping it brings the dialog back.
- Background the app during sync — verify Dynamic Island shows "Syncing Tape" (iOS 26+).
- Test upload-only and download-only scenarios still use their respective individual coordinators with their own dialogs.
- Test cancellation mid-sync — verify both coordinators are cancelled.
- Test upload failure during sync — verify error surfaces and download phase is skipped.
