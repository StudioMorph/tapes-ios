# Merge and Save

## Summary
Single-entry-point export that merges all clips in a tape (with transitions and background music) into a 1080p HEVC MP4 and saves it to the Photos library, with full progress UI, background support, and local notifications.

## Purpose & Scope
Replaces the previous broken `TapeExporter` with a new implementation that reuses `TapeCompositionBuilder` — the same composition pipeline used for playback — ensuring the exported video matches what the user sees during preview. Includes a complete progress UX with dismissible dialogs, header indicator, completion feedback, and local notifications.

## Entry Point
- **Tape card arrow.down icon** → confirmation alert → Save → `ExportCoordinator.exportTape(_:)`.
- Play button on the card opens playback only; no merge/save dialog.

## Key Components

| Component | Role |
|-----------|------|
| `TapeExportSession` | Class-based exporter holding the `AVAssetExportSession` for progress polling and cancellation. Builds composition via `TapeCompositionBuilder`, adds music, exports, saves to Photos. |
| `ExportCoordinator` | Manages export lifecycle: progress polling (Timer-based), ETA calculation, cancellation, completion feedback (sound + haptics), local notifications, and dialog state. |
| `GlassAlertCard` | Reusable glass-styled alert component (`DesignSystem/`) with generic icon and message content, edge highlight, and three button styles (primary, secondary, destructive). Used by both progress and completion dialogs. |
| `ExportProgressDialog` | Uses `GlassAlertCard` with a custom `CircularProgressRing` icon, ETA/hint message content, and Cancel Merge (destructive) / OK (primary) buttons. |
| `ExportCompletionDialog` | Uses `GlassAlertCard` with `systemImage` convenience init and "Done" (secondary) / "Show in Photos" (primary) buttons. |
| `CircularProgressRing` | Shared SwiftUI component used in the progress dialog and the header indicator. |
| `HeaderView` (export indicator) | Shows a small circular progress ring with arrow.down icon next to "TAPES" when export is running and dialog is dismissed. Tapping reopens the progress dialog. |
| `ExportNotificationHandler` | `UNUserNotificationCenterDelegate` set up in `TapesApp`. Handles notification tap → opens Photos app. |

## Data Flow
1. User taps arrow.down → system alert → Save.
2. `TapeCardView.onMergeAndSave()` → `TapesListView.handleMergeAndSave(_:)` → `ExportCoordinator.exportTape(_:)`.
3. Coordinator creates a `TapeExportSession`, shows progress dialog, starts progress polling timer (0.5s interval).
4. `TapeExportSession.run(tape:)` builds composition, adds music, runs `AVAssetExportSession`, saves to Photos.
5. During export, `ExportCoordinator` polls `session.sessionProgress` and maps it to 0–95% overall progress. ETA is calculated from elapsed time and progress ratio.
6. User can dismiss the dialog (export continues in background). On first dismiss, notification permission is requested.
7. While dialog is dismissed, header shows a circular progress indicator. Tapping reopens the dialog.
8. On completion:
   - **App in foreground:** system sound (1007) + double haptic + completion dialog with "Done" / "Show in Photos".
   - **App in background:** local notification. Tapping notification opens Photos app.
9. User can cancel at any time via "Cancel Merge" button, which calls `AVAssetExportSession.cancelExport()`.

## What Changed from Previous Implementation
- **`TapeExporter` enum → `TapeExportSession` class** with stored `AVAssetExportSession` reference for progress reading and cancellation.
- **Progress UI** replaced: old `ExportProgressOverlay` (non-dismissible full-screen overlay) and `CompletionToast` (auto-dismiss toast) replaced by custom HIG-inspired dialogs with interactive buttons.
- **Header indicator** added: circular progress ring next to "TAPES" title when export is backgrounded.
- **ETA calculation** added based on elapsed time and export progress.
- **Cancellation support** added via `TapeExportSession.cancel()`.
- **Completion feedback**: system sound + double haptic on success.
- **Local notifications**: sent when export completes while app is in background; tap opens Photos.
- **Notification permission** requested on first dialog dismiss (not at launch).

## Testing / QA Considerations
- Export a tape with 1 clip → should save with correct orientation and music.
- Export a tape with 2+ clips → should include transitions matching playback.
- Export a tape with image clips → images should appear as video segments with smooth motion.
- Export a tape with trimmed clips → only trimmed portion should appear.
- Export a tape with background music → music should be audible, looped, with fade-out.
- Export a tape with no music (mood = none) → clip audio only.
- Deny Photos permission → should show error, not crash.
- Dismiss progress dialog → header indicator visible, tapping reopens dialog.
- Cancel mid-export → export stops, UI resets.
- Complete export while app is backgrounded → local notification appears; tapping opens Photos.
- Complete export while app is foregrounded → sound + haptic + completion dialog.
- "Show in Photos" → opens Photos app.
