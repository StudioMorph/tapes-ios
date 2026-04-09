# Live Photos

Treat Live Photos as short video clips within a tape, using the paired video component that iOS stores alongside each Live Photo.

## Purpose & Scope

Live Photos contain a ~3-second video paired with a still image. This feature lets users play that motion video during tape playback and export, giving tapes a more dynamic feel without requiring users to have shot separate video clips.

The feature is controlled at two levels:

- **Tape-level default** — a toggle in Tape Settings that applies to every Live Photo in the tape.
- **Clip-level override** — a toggle in Image Settings (only visible for Live Photo clips) that overrides the tape default for that individual clip.

## Key UI Components

### Tape Settings (`TapeSettingsView`)

A "Live Photos" section with an inline toggle and explanatory text. When ON (default), all Live Photos in the tape play as short videos.

### Image Settings (`ImageClipSettingsView`)

For Live Photo clips only, a "Live Photo" section appears at the top with its own toggle. When the toggle is ON, the motion style and duration sections are greyed out and disabled (since the clip plays as a video, not a still image). The per-clip override is stored as `nil` when it matches the tape default (to inherit future changes).

### Carousel Badge (`ClipInfoBadge`)

Live Photo clips show the `livephoto` SF Symbol and "Live Photo" text instead of the usual media type icon and duration.

## Data Flow

### Model

- **`Clip.isLivePhoto: Bool`** — set during import when the `PHAsset` has `.photoLive` media subtype.
- **`Clip.livePhotoAsVideo: Bool?`** — per-clip override (`nil` = use tape default).
- **`Clip.shouldPlayAsLiveVideo(tapeDefault:)`** — computed helper that resolves the effective setting.
- **`Tape.livePhotosAsVideo: Bool`** — tape-level default (default: `true`).

### Import (`MediaImportCoordinator` → `MediaProviderLoader`)

During `resolvePickedMedia`, the `PHAsset.mediaSubtypes` is checked for `.photoLive`. The `PickedMedia.photo` case carries an `isLivePhoto` flag, which is propagated to the `Clip` during `buildClip`.

### Playback & Export (`TapeCompositionBuilder`)

`resolveAsset(for:)` checks `clip.shouldPlayAsLiveVideo(tapeDefault:)`. When true, it calls `extractLivePhotoVideo(assetIdentifier:)` which uses `PHAssetResourceManager` to write the `.pairedVideo` resource to a temporary file, returning an `AVURLAsset` that slots into the existing video pipeline.

The builder receives the tape-level `livePhotosAsVideo` flag via its initialiser (set by `TapeExporter` and `TapePlayerViewModel`).

### Video Extraction (`MediaProviderLoader`)

`extractLivePhotoVideo(assetIdentifier:)`:
1. Fetches the `PHAsset` and its `PHAssetResource` list.
2. Finds the `.pairedVideo` resource.
3. Writes it to `tmp/LivePhotoVideos/` via `PHAssetResourceManager.writeData(for:toFile:options:)`.
4. Loads the duration from the resulting `AVURLAsset`.

## Testing / QA Considerations

- Import a mix of Live Photos and regular photos — verify `isLivePhoto` is correctly set.
- Toggle tape-level setting and verify all Live Photo clips switch between video and still playback.
- Override a single clip and verify it behaves independently of the tape toggle.
- Export with Live Photos as video and verify the paired video appears in the final output.
- Verify the carousel badge shows "Live Photo" icon and text for Live Photo clips.
- Test with iCloud-only Live Photos (network access is enabled on the resource request).
- Verify backward compatibility — existing tapes without the new fields should decode with `isLivePhoto = false` and `livePhotosAsVideo = true`.
