# Merge and Save

## Summary
Single-entry-point export that merges all clips in a tape (with transitions and background music) into a 1080p MP4 and saves it to the Photos library.

## Purpose & Scope
Replaces the previous broken `TapeExporter` with a new implementation that reuses `TapeCompositionBuilder` — the same composition pipeline used for playback — ensuring the exported video matches what the user sees during preview.

## Entry Point
- **Tape card arrow.down icon** → confirmation alert → Save → `ExportCoordinator.exportTape(_:)`.
- Play button on the card opens playback only; no merge/save dialog.

## Key Components

| Component | Role |
|-----------|------|
| `TapeCompositionBuilder.buildExportComposition(for:)` | Builds `AVMutableComposition` + `AVMutableVideoComposition` + `AVMutableAudioMix` using the same pipeline as playback. |
| `TapeExporter.export(tape:)` | Calls the builder, adds background music track (looped, with fade-out), runs `AVAssetExportSession`, saves to Photos. |
| `iOSExporterBridge` | Thin async pass-through to `TapeExporter`. |
| `ExportCoordinator` | Manages export lifecycle, permissions, progress overlay, completion toast, and error alert. |

## Data Flow
1. User taps arrow.down → alert → Save.
2. `TapeCardView.onMergeAndSave()` → `TapesListView.handleMergeAndSave(_:)` → `ExportCoordinator.exportTape(_:)`.
3. Coordinator requests Photos permission, then calls `iOSExporterBridge.export(tape:)`.
4. `TapeExporter` uses `TapeCompositionBuilder.buildExportComposition(for:)` to get the composition.
5. If `tape.musicMood != .none`, the cached Mubert track is loaded, looped to cover the video duration, and mixed at `tape.musicVolume` with a 1.5s fade-out.
6. `AVAssetExportSession` exports 1080p MP4 with the composition's video instructions and audio mix.
7. Exported file is saved to Photos via `PHPhotoLibrary.performChanges`.
8. Coordinator associates the asset with the tape's album via `TapeAlbumService`.

## What Changed from Previous Implementation
- **Old `TapeExporter`** built its own `AVMutableComposition` with overlapping video instructions (broke for 2+ clips), hardcoded crossfade transitions, ignored trim/image clips, and had no background music.
- **New `TapeExporter`** delegates composition building to `TapeCompositionBuilder`, which correctly handles transitions, trim, image clips, scale modes, and orientation.
- **Background music** is now mixed into the export (was previously only played during live preview via `BackgroundMusicPlayer`).
- **ExportCoordinator** modernised to use `async/await` instead of completion handlers.

## Testing / QA Considerations
- Export a tape with 1 clip → should save with correct orientation and music.
- Export a tape with 2+ clips → should include transitions matching playback.
- Export a tape with image clips → images should appear as video segments.
- Export a tape with trimmed clips → only trimmed portion should appear.
- Export a tape with background music → music should be audible, looped, with fade-out.
- Export a tape with no music (mood = none) → clip audio only.
- Deny Photos permission → should show error, not crash.
