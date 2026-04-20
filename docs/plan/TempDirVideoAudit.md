# Temp-Dir Video Persistence Audit

**Status:** draft, awaiting approval.
**Scope:** iOS only. Primarily an investigation; likely results in a small fix + targeted migration.
**Risk:** low as investigation. Medium if the investigation uncovers a real data-loss path (which it might).
**Deploy posture:** iOS-only, ships with next build.

---

## Problem

[Tapes/Platform/Photos/MediaProviderLoader.swift:44](../../Tapes/Platform/Photos/MediaProviderLoader.swift:44), in `loadMovieURL(from:)`:

```swift
let importsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
try? FileManager.default.createDirectory(at: importsDir, withIntermediateDirectories: true)
let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
let dest = importsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
try FileManager.default.copyItem(at: src, to: dest)
```

PHPicker gives us a temporary URL; we copy it into `tmp/Imports/…`. The resulting URL is stored as `Clip.localURL` and persists into `tapes.json`.

**iOS can purge `tmp`** under storage pressure or on reboot. Worse: our own code does it. [TapesApp.init:17](../../Tapes/TapesApp.swift:17) calls `cleanupTempImports()`, which removes `tmp/Imports/` entirely on *every* launch.

That means: any clip whose `localURL` points at `tmp/Imports/*.mov` has a dangling reference after the next app launch.

---

## What saves us today (partly)

`Clip.assetLocalId` is the preferred path. When a clip is imported from the Photos library via PHPicker with `assetIdentifier` set, iOS returns the `PHAsset.localIdentifier` and we store that. On playback, `TapeCompositionBuilder+AssetResolution` can resolve the asset directly from Photos, bypassing `localURL` entirely.

When clips *also* have a `localURL` alongside their `assetLocalId`, losing the local file is harmless — the Photos asset is still there and we re-fetch.

**The concern:** are there code paths where a clip ends up with only `localURL` (pointing at `tmp/Imports/`) and no `assetLocalId`? If so, app relaunch silently breaks that clip.

---

## Investigation plan

### Step 1 — Audit `PickedMedia` construction

`resolvePickedMedia(from:)` in [MediaProviderLoader.swift:141](../../Tapes/Platform/Photos/MediaProviderLoader.swift:141):

```swift
if let assetIdentifier = result.assetIdentifier,
   let asset = fetchPHAsset(localIdentifier: assetIdentifier) {
    switch asset.mediaType {
    case .video:
        let seconds = asset.duration
        return .video(url: nil, duration: seconds, assetIdentifier: assetIdentifier)
    // …
    }
}

if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
    let url = try await loadMovieURL(from: result)
    let seconds = durationFromPhotos(assetIdentifier: result.assetIdentifier)
    return .video(url: url, duration: seconds, assetIdentifier: result.assetIdentifier)
}
```

Case A (happy path): `assetIdentifier` present + `fetchPHAsset` succeeds → return video with `url: nil`, just the identifier. Safe.

Case B (tmp-backed path): `assetIdentifier` missing, or `fetchPHAsset` returns `nil` (permission limited, asset not found) → call `loadMovieURL`, return video with `url: tmp-URL, assetIdentifier: result.assetIdentifier` — *note `assetIdentifier` may still be non-nil*. So this clip will *also* have the local file.

The question: when does `PHPicker` return a result where `assetIdentifier` is nil? According to Apple's docs, when the user has selected Photos access as "Limited" and the picker was configured without `filter:` requesting Photos library items, `assetIdentifier` can be nil. Also, shared-from-another-app files routed through PHPicker may arrive without an asset identifier.

### Step 2 — Trace `Clip.fromVideo` and `makeVideoClip` call sites

Clips with `localURL` but no `assetLocalId` are created by:

- `Clip.fromVideo(url:duration:thumbnail:assetLocalId:)` — `assetLocalId` defaults to `nil`.
- `TapesStore.makeVideoClip(url:duration:assetIdentifier:)` — takes an `assetIdentifier` but it's optional.

Where are these called with `assetIdentifier == nil`?

1. **Camera capture path.** `CameraCoordinator` / `CaptureService` writes recordings to a temp URL and creates a clip from it. The clip has `localURL` set and no asset identifier — because the video was just captured and isn't in the Photos library yet. Until [associated with an album](../../Tapes/Platform/Photos/TapeAlbumService.swift), it has no PHAsset at all.
2. **Drag-and-drop from other apps via `tapes://` file opening.** If such a flow exists — audit required.

For (1), the Camera flow eventually associates the clip with a Photos album, which gives it an asset identifier. Question: does the association back-fill `assetLocalId` on the existing `Clip`? Looking at `TapesStore.associateClipsWithAlbum` — it takes asset identifiers, not clip URLs. So **captured videos never get their `assetLocalId` filled unless the association path explicitly does so.**

This is the gap. If a user captures a video via the custom camera, closes the app, relaunches, the `tmp/Imports` dir is wiped in `cleanupTempImports`, and the clip's `localURL` is broken. The clip might have no `assetLocalId` (the association wrote assets into an album but didn't update the `Clip`).

**Confirming this requires reading the camera-save pipeline** carefully. `CameraCoordinator.performSave` saves to Photos, gets a `PHAsset.placeholderForCreatedAsset.localIdentifier`, then creates a clip. I need to verify the resulting `Clip` has both `localURL` (for immediate playback before the PHAsset is fully committed) *and* `assetLocalId` (so the PHAsset is used after relaunch).

### Step 3 — Once we know where the gap is, close it

Depending on what Step 2 reveals, the fix is one of:

**Option A: Guarantee every persisted clip has a PHAsset backing.**

When a clip is created from a camera capture, save to Photos first, get the asset identifier, then create the Clip with both `localURL` and `assetLocalId`. On playback, prefer the PHAsset. The local URL can still break silently across launches — but the PHAsset fallback preserves the data.

**Option B: Move `tmp` imports to Application Support.**

Don't use `tmp/Imports`; use `Application Support/Imports/`. OS won't purge it. `TapesApp.init`'s `cleanupTempImports()` targets `tmp/Imports` specifically, so moving the directory decouples the two. Clips' `localURL` remains valid across launches.

This is what `moveToPersistentStorage` in `MediaProviderLoader.swift:266` already offers — but nothing calls it.

**Option C: Both.**

In practice, I'd want both. Option A is the correct semantic ("every clip has a real PHAsset") and makes Photos album integration cleaner. Option B is the defensive measure that prevents silent data loss in the meantime.

### Step 4 — Migration for existing clips

For any existing tapes with clips whose `localURL` points at a tmp path, one-time migration on launch:

```swift
// Pseudocode for the migration loop
for tape in tapes {
    for clip in tape.clips where clip.localURL?.path.contains("/tmp/") ?? false {
        if clip.assetLocalId != nil {
            // PHAsset is the source of truth — just clear the dead URL
            clip.localURL = nil
        } else {
            // Try to find a matching PHAsset by content (hash or creation date)
            // If found, set assetLocalId and clear localURL.
            // If not found, log + continue; the clip may be dead data.
        }
    }
}
```

The "try to find a matching PHAsset by content" step is non-trivial — PHAssets don't expose content hashes easily. Alternative: if we can't recover, flag the clip as broken and show the user a "this clip was lost, tap to re-add from Photos" affordance. That's out of scope for this plan but worth raising.

---

## What this plan produces

1. **An audit report** — for each code path that creates a `Clip`, whether the resulting clip has only `localURL`, only `assetLocalId`, or both. Short doc, ~1 page.
2. **A targeted fix** — the smallest change that closes the identified gap. Likely: camera-save pipeline back-fills `assetLocalId` on the Clip. Plus `MediaProviderLoader.loadMovieURL` writes to Application Support instead of tmp, so any remaining tmp-only paths are eliminated.
3. **A one-time launch migration** for existing tapes — detect tmp-based URLs, strip them if a PHAsset is available, otherwise flag.
4. **A test for the migration** — create a tape with a tmp-backed clip in a unit test, run migration, confirm behaviour.

---

## Risks

- **During Step 2, we might discover the bug is real and has been losing user data for a while.** If so, the blast radius for current internal testing is small (two devices). For TestFlight and beyond, it matters.
- **Moving imports to Application Support increases persistent storage.** Application Support is included in iCloud backup. Videos can be large. Setting `.isExcludedFromBackupKey = true` on the directory prevents unbounded iCloud growth.
- **The migration has to be careful not to strip useful `localURL`s.** A clip might have a non-tmp `localURL` (camera capture in Application Support) that's still valid. The migration only targets `/tmp/` paths.

---

## Verification

1. Audit the code paths, produce the report, share with you before any code change. This is the "investigation" output.
2. Once we agree on the fix shape, implement + unit-test the migration.
3. Device test: capture a video via the custom camera, immediately relaunch the app, confirm the clip still plays. Repeat without relaunch — confirm no regression.
4. Device test: old tape with possibly-tmp-backed clips from prior builds — let the migration run, confirm the tape still plays or the clip is explicitly flagged.

---

## Deploy

iOS-only, next build.

---

## Open questions

- **Is the camera-save pipeline currently back-filling `assetLocalId`?** This is the investigation's central question. I need to read `CameraCoordinator.performSave` carefully before I can write the fix. The plan above describes the shape of the fix assuming "no, it isn't", because that's what the review suspected — but the audit confirms one way or the other.
- **What do we do about clips that can't be recovered?** If migration finds a tmp-backed clip with no PHAsset and no content-hash match, do we delete it, mark it broken, or leave it and let playback fail gracefully? Worth discussing before implementing.
