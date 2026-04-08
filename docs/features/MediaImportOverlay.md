# Media Import Overlay

## Summary

Full-screen import overlay that resolves all picked media before inserting any clips into the tape, replacing the previous placeholder-based incremental loading approach.

## Purpose & Scope

When a user selects multiple media items from the system photo picker, the app now shows a full-screen glass overlay with a circular progress indicator, "Importing X/Y" text, and a Cancel button. No placeholder clips are inserted into the carousel during import. All media is resolved behind the overlay, and only on successful completion are all clips inserted into the tape in a single batch.

## Key UI Components

- **ImportProgressOverlay** — Full-screen view using `GlassAlertCard` with `CircularProgressRing`, progress label, and cancel button.
- **MediaImportCoordinator** — `ObservableObject` that manages the resolution of `PHPickerResult` items into `Clip` instances, tracking progress and supporting cancellation.

## Data Flow

1. User selects media in `SystemMediaPicker` (PHPickerViewController).
2. `TapeCardView` calls `importCoordinator.startImport(results:tapeID:insertionIndex:)`.
3. `MediaImportCoordinator` resolves each `PHPickerResult` sequentially via `resolvePickedMedia(from:)`, building `Clip` instances.
4. `ImportProgressOverlay` (in `TapesListView`) observes coordinator state and shows the overlay.
5. On completion, `TapeCardView` observes `isImporting` becoming `false`, calls `consumeResults(for:)`, and inserts all clips in one batch via `TapesStore.insert(_:into:at:)`.
6. On cancellation, the coordinator discards all resolved clips and resets.

## Testing / QA Considerations

- Verify overlay appears immediately when picker dismisses with selections.
- Verify progress increments for each resolved item.
- Verify Cancel discards all clips — no clips appear in tape.
- Verify successful import inserts all clips at the correct position.
- Verify carousel scrolls to correct position after batch insert.
- Verify first-content side effect (empty tape creation) still triggers.
- Verify camera capture path (which bypasses the coordinator) still works.

## Related Tickets

None.
