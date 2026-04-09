# Live Photos

Treat Live Photos as short video clips within a tape, using the paired video component that iOS stores alongside each Live Photo.

## Purpose & Scope

Live Photos contain a ~3-second video paired with a still image. This feature lets users play that motion video during tape playback and export, giving tapes a more dynamic feel without requiring users to have shot separate video clips.

The feature is controlled at two levels:

- **Tape-level default** — a toggle in Tape Settings that applies to every Live Photo in the tape.
- **Clip-level override** — a toggle in Image Settings (only visible for Live Photo clips) that overrides the tape default for that individual clip.

### Mute Sound

Live Photo videos include ambient audio. A "Mute sound" toggle is available at both the tape and clip level, mirroring the play-as-video toggle hierarchy. When muted, the audio track from the paired video is stripped during composition building, so neither playback nor export includes sound for that clip. The mute toggle is disabled when Live Photo video playback is off (since there is no video audio to mute).

## Key UI Components

### Tape Settings (`TapeSettingsView`)

A "Live Photos" section with two toggles: "Play as video" (on by default) and "Mute sound" (on by default). The mute toggle is disabled and dimmed when video playback is off.

### Image Settings (`ImageClipSettingsView`)

For Live Photo clips only, a "Live Photo" section appears at the top with "Play as video" and "Mute sound" toggles. When video playback is ON, the motion style and duration sections are greyed out and disabled. Both per-clip overrides are stored as `nil` when they match the tape default (to inherit future changes).

### Carousel Badge (`ClipInfoBadge`)

Live Photo clips show the `livephoto` SF Symbol and "Live Photo" text instead of the usual media type icon and duration.

## Data Flow

### Model

- **`Clip.isLivePhoto: Bool`** — set during import when the `PHAsset` has `.photoLive` media subtype.
- **`Clip.livePhotoAsVideo: Bool?`** — per-clip override (`nil` = use tape default).
- **`Clip.livePhotoMuted: Bool?`** — per-clip mute override (`nil` = use tape default).
- **`Clip.shouldPlayAsLiveVideo(tapeDefault:)`** — computed helper that resolves the effective video setting.
- **`Clip.shouldMuteLiveAudio(tapeDefault:)`** — computed helper that resolves the effective mute setting.
- **`Tape.livePhotosAsVideo: Bool`** — tape-level default (default: `true`).
- **`Tape.livePhotosMuted: Bool`** — tape-level mute default (default: `true`).

### Import (`MediaImportCoordinator` → `MediaProviderLoader`)

During `resolvePickedMedia`, the `PHAsset.mediaSubtypes` is checked for `.photoLive`. The `PickedMedia.photo` case carries an `isLivePhoto` flag, which is propagated to the `Clip` during `buildClip`.

### Playback & Export (`TapeCompositionBuilder`)

`resolveAsset(for:)` checks `clip.shouldPlayAsLiveVideo(tapeDefault:)`. When true, it calls `extractLivePhotoVideo(assetIdentifier:)` which uses `PHAssetResourceManager` to write the `.pairedVideo` resource to a temporary file, returning an `AVURLAsset` that slots into the existing video pipeline.

The builder receives both `livePhotosAsVideo` and `livePhotosMuted` tape-level flags via its initialiser (set by `TapeExporter` and `TapePlayerViewModel`). When a clip is muted, the audio track is excluded from the `ClipAssetContext`, so no audio is inserted into the composition for that clip.

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
- Toggle mute ON — verify no audio during playback and in exported video for Live Photo clips.
- Toggle mute OFF — verify audio is present.
- Override mute per-clip and verify it acts independently of the tape default.
- Verify the mute toggle is disabled when video playback is off.
- Verify backward compatibility — existing tapes without the new fields should decode with `isLivePhoto = false`, `livePhotosAsVideo = true`, and `livePhotosMuted = true`.
