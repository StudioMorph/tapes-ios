# Timeline Asset Intake Audit & Refactor Plan

**Status:** ✅ **COMPLETED** - See [`docs/features/TimelineAssetIntakeOptimization.md`](./features/TimelineAssetIntakeOptimization.md)

**Date:** 2024  
**Goal:** Stop eagerly resolving/downloading full video assets when adding items via picker. Load only thumbnails + metadata for timeline/carousel. Defer AVAsset resolution to playback/export.

**Result:** Timeline builds **incredibly fast** with high-quality Retina thumbnails. Zero AVAsset creation, zero iCloud downloads during intake.

---

## Executive Summary

**Current State:** System eagerly loads full video files and creates AVAsset instances during picker intake, causing:
- File copying/downloading for all selected videos (even iCloud-backed)
- AVAsset creation to read duration metadata
- Potential iCloud downloads triggered at add time
- Memory overhead (full video files in temp storage)

**Target State:** Load only thumbnails + lightweight metadata at intake. Defer AVAsset resolution to playback/export pipeline.

---

## Current Flow Analysis

### Entry Points: Picker Results Processing

**1. Primary Intake Path (`TapeCardView.swift`)**
```270:305:Tapes/Views/TapeCardView.swift
.sheet(isPresented: $showingMediaPicker) {
    SystemMediaPicker(
        isPresented: $showingMediaPicker,
        allowImages: true,
        allowVideos: true
    ) { results in
        TapesLog.mediaPicker.info("🧩 onPick count=\(results.count, privacy: .public)")
        guard !results.isEmpty else { return }

        Task {
            let tapeID = tape.id
            var placeholderIDs: [UUID] = []
            await MainActor.run {
                // ... insertion index calculation ...
                placeholderIDs = tapeStore.insertPlaceholderClips(
                    count: results.count,
                    into: tapeID,
                    at: insertionIndex
                )
            }
            if !placeholderIDs.isEmpty {
                tapeStore.processPickerResults(results, placeholderIDs: placeholderIDs, tapeID: tapeID)
            }
        }
    }
}
```

**Flow:** Picker → `processPickerResults` → `resolvePickedMedia` → Build Clip → Insert into Tape

---

## Eager AVAsset/Download Operations

### Critical Issue #1: Video File Copying + AVAsset Creation

**Location:** `Tapes/Platform/Photos/MediaProviderLoader.swift:140-156`

```140:156:Tapes/Platform/Photos/MediaProviderLoader.swift
func resolvePickedMedia(from result: PHPickerResult) async throws -> PickedMedia {
    if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        let url = try await loadMovieURL(from: result)  // ❌ Copies file eagerly
        let asset = AVURLAsset(url: url)                // ❌ Creates AVAsset
        let duration = try? await asset.load(.duration) // ❌ Loads duration eagerly
        let seconds = duration?.seconds ?? 0
        return .video(url: url, duration: seconds, assetIdentifier: result.assetIdentifier)
    }

    if result.itemProvider.canLoadObject(ofClass: UIImage.self) ||
        result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        let image = try await loadImage(from: result)
        return .photo(image: image, assetIdentifier: result.assetIdentifier)
    }

    throw MediaLoaderError.loadFailed(nil)
}
```

**Problem:** 
- `loadMovieURL()` (line 23-61) calls `loadFileRepresentation` which **copies entire video file** to temp directory
- Creates `AVURLAsset` to read duration (may trigger iCloud download if file not local)
- All video files copied even if just for timeline display

**Line References:**
- `MediaProviderLoader.swift:23` - `loadMovieURL()` - file copying
- `MediaProviderLoader.swift:143` - `AVURLAsset(url: url)` - asset creation
- `MediaProviderLoader.swift:144` - `asset.load(.duration)` - eager duration loading

---

### Critical Issue #2: Fallback AVAsset Creation for Duration

**Location:** Multiple places check duration and create AVAsset if missing

**1. `TapesStore.swift:464`** (in `buildClip`):
```459:478:Tapes/ViewModels/TapesStore.swift
private func buildClip(from media: PickedMedia) -> Clip? {
    switch media {
    case let .video(url, duration, assetIdentifier):
        var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
        if clip.duration <= 0 {
            let asset = AVURLAsset(url: url)              // ❌ Creates AVAsset
            let seconds = CMTimeGetSeconds(asset.duration) // ❌ Synchronous duration access
            clip.duration = seconds > 0 ? seconds : 0
        }
        return clip
    case let .photo(image, assetIdentifier):
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        return Clip.fromImage(
            imageData: data,
            duration: Tokens.Timing.photoDefaultDuration,
            thumbnail: image,
            assetLocalId: assetIdentifier
        )
    }
}
```

**2. `TapesStore.swift:746`** (in `insertMedia`):
```743:752:Tapes/ViewModels/TapesStore.swift
case let .video(url, duration, assetIdentifier):
    var videoClip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
    if videoClip.duration <= 0 {
        let asset = AVURLAsset(url: url)              // ❌ Creates AVAsset
        let seconds = CMTimeGetSeconds(asset.duration) // ❌ Synchronous duration access
        if seconds > 0 {
            videoClip.duration = seconds
        }
    }
    clip = videoClip
```

**3. `TapesStore.swift:799`** (in `insertAtCenter`):
```796:804:Tapes/ViewModels/TapesStore.swift
var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
if clip.duration <= 0 {
    let asset = AVURLAsset(url: url)              // ❌ Creates AVAsset
    let seconds = CMTimeGetSeconds(asset.duration) // ❌ Synchronous duration access
    if seconds > 0 {
        clip.duration = seconds
    }
}
```

**4. `TapesStore.swift:859`** (in `insertAtCenter(into:picked:)`):
```857:864:Tapes/ViewModels/TapesStore.swift
var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
if clip.duration <= 0 {
    let asset = AVURLAsset(url: url)              // ❌ Creates AVAsset
    let seconds = CMTimeGetSeconds(asset.duration) // ❌ Synchronous duration access
    if seconds > 0 {
        clip.duration = seconds
    }
}
```

**5. `TapeCardView.swift:367`** (in `makeClips`):
```364:372:Tapes/Views/TapeCardView.swift
case let .video(url, duration, assetIdentifier):
    var clip = Clip.fromVideo(url: url, duration: duration, thumbnail: nil, assetLocalId: assetIdentifier)
    if clip.duration <= 0 {
        let asset = AVURLAsset(url: url)              // ❌ Creates AVAsset
        let seconds = CMTimeGetSeconds(asset.duration) // ❌ Synchronous duration access
        if seconds > 0 {
            clip.duration = seconds
        }
    }
    clips.append(clip)
```

**Problem:** All these paths create `AVURLAsset` synchronously to read duration if not provided. This may trigger file system access or iCloud downloads.

---

### Critical Issue #3: Background Thumbnail/Duration Generation

**Location:** `TapesStore.swift:951-954`

```951:954:Tapes/ViewModels/TapesStore.swift
func generateThumbAndDuration(for url: URL, clipID: UUID, tapeID: UUID) {
    let asset = AVURLAsset(url: url)  // ❌ Creates AVAsset
    processAssetMetadata(asset, clipID: clipID, tapeID: tapeID)
}
```

**Called from:**
- `TapesStore.swift:435` - After `applyResolvedMedia` for videos
- `TapesStore.swift:891` - After `insertAtCenter(into:picked:)` for videos
- `TapesStore.swift:909` - After `insert(_:into:at:)` for videos
- `TapesStore.swift:1064` - After tape load (missing metadata)

**Problem:** Creates AVAsset and loads duration + generates thumbnail in background. If URL is iCloud-backed, this triggers download.

---

### Critical Issue #4: Photos Asset AVAsset Resolution

**Location:** `TapesStore.swift:1110`

```1106:1135:Tapes/ViewModels/TapesStore.swift
let options = PHVideoRequestOptions()
options.deliveryMode = .automatic
options.isNetworkAccessAllowed = true  // ❌ Allows iCloud download

PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
    guard let avAsset else { return }
    let durationSeconds = CMTimeGetSeconds(avAsset.duration)

    Task { @MainActor in
        self.updateClip(clipID, transform: { clip in
            clip.duration = durationSeconds
            clip.updatedAt = Date()
        }, in: tapeID)
    }

    if let urlAsset = avAsset as? AVURLAsset {
        self.generateThumbAndDuration(for: urlAsset.url, clipID: clipID, tapeID: tapeID)
    } else {
        // Generate thumbnail from AVAsset
        let generator = AVAssetImageGenerator(asset: avAsset)
        // ... thumbnail generation ...
    }
}
```

**Called from:** `regenerateMetadataFromPhotoLibrary` (line 1087) - for Photos assets missing duration/thumbnail

**Problem:** 
- `isNetworkAccessAllowed = true` - **Triggers iCloud downloads**
- Creates full AVAsset for Photos videos
- Called during tape load or metadata regeneration

---

### Issue #5: PhotoImportCoordinator AVAsset Usage

**Location:** `Tapes/Features/Import/PhotoImportCoordinator.swift:93-111`

```93:111:Tapes/Features/Import/PhotoImportCoordinator.swift
private func generateThumbnail(from url: URL) async -> UIImage? {
    let asset = AVAsset(url: url)                      // ❌ Creates AVAsset
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.maximumSize = CGSize(width: 320, height: 320)

    do {
        let cgImage = try await imageGenerator.image(at: .zero).image
        return UIImage(cgImage: cgImage)
    } catch {
        TapesLog.mediaPicker.error("Failed to generate thumbnail: \(error.localizedDescription)")
        return nil
    }
}

private func getVideoDuration(url: URL) async -> TimeInterval {
    let asset = AVAsset(url: url)                      // ❌ Creates AVAsset
    let duration = try? await asset.load(.duration)
    return CMTimeGetSeconds(duration ?? .zero)
}
```

**Problem:** Alternative import path also creates AVAsset eagerly for thumbnails and duration.

---

## Current Thumbnail Storage

**Model:** `Clip.thumbnail: Data?` (JPEG Data)
**Computed Property:** `Clip.thumbnailImage: UIImage?` (line 203-206)

**Display:** `ThumbnailView.swift:96`
```96:100:Tapes/Components/ThumbnailView.swift
if let thumbnail = clip.thumbnailImage {
    Image(uiImage: thumbnail)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .clipped()
}
```

**Current Approach:**
- Thumbnails stored as JPEG Data in Clip model
- Generated from full video files via `AVAssetImageGenerator`
- Or from UIImage for photos
- Stored persistently with Tape (in JSON)

**Problem:** Thumbnails generated from full video files (which may trigger iCloud downloads).

---

## Proposed Approach

### 1. Lightweight Clip Model (Timeline Only)

**New Type:** `TapeClipRef` (or extend `Clip` to support metadata-only mode)

```swift
struct TapeClipMetadata: Codable {
    let id: UUID
    let assetLocalId: String?        // PHAsset.localIdentifier
    let mediaType: PHAssetMediaType
    let duration: TimeInterval       // From PHAsset.duration (not AVAsset)
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    
    // No AVAsset, no localURL (for Photos assets)
    // localURL only populated for camera-captured videos
}
```

**Migration Strategy:** Keep existing `Clip` model but don't populate `localURL` or require AVAsset for Photos assets. Use `assetLocalId` as primary identifier.

---

### 2. Thumbnail Loading via PHCachingImageManager

**New Service:** `TimelineThumbnailProvider`

**Key Features:**
- Use `PHImageManager.requestImage()` with target size = carousel cell size × scale (e.g., 2×)
- `PHImageRequestOptions.isNetworkAccessAllowed = false` for timeline requests
- `PHImageRequestOptions.deliveryMode = .opportunistic` (fast, may be degraded)
- `PHImageRequestOptions.resizeMode = .fast`

**Preheat/Cancel:**
- `PHCachingImageManager.startCachingImages()` for visible + adjacent clips
- `PHCachingImageManager.stopCachingImages()` when clips scroll out of view
- Cancel pending requests on scroll

---

### 3. Metadata Extraction from PHAsset

**For Photos Assets:**
- `PHAsset.duration` - Use directly (no AVAsset needed)
- `PHAsset.pixelWidth` / `pixelHeight` - Direct access
- `PHAsset.creationDate` - Direct access
- `PHAsset.mediaType` - Direct access

**For Local Files (Camera):**
- Use `PHPickerResult.assetIdentifier` if available
- Or extract metadata from file URL without creating AVAsset (use `AVURLAsset` with `loadValuesAsynchronously` but only for metadata keys)

---

### 4. Deferred AVAsset Resolution

**When to Resolve:**
- **Playback:** `TapeCompositionBuilder.resolveVideoAsset()` - already handles this
- **Export:** `TapeExporter` - already handles this
- **Settings/Edit:** Only when needed for preview

**Current Playback Path:** Already defers to `TapeCompositionBuilder.fetchAVAssetFromPhotos()` with `isNetworkAccessAllowed = true` - ✅ Good

---

## Implementation Diffs

### Diff 1: Modify `resolvePickedMedia` to Get Metadata Without AVAsset

**File:** `Tapes/Platform/Photos/MediaProviderLoader.swift`

**Change:**
- If `result.assetIdentifier` exists, fetch PHAsset and read metadata directly
- Only request thumbnail via `PHImageManager.requestImage()` (no AVAsset)
- Don't copy video file if Photos asset
- For local files (camera), still copy but don't create AVAsset for duration

**Code:**
```swift
func resolvePickedMedia(from result: PHPickerResult) async throws -> PickedMedia {
    // If Photos asset, use PHAsset metadata
    if let assetIdentifier = result.assetIdentifier {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        if let phAsset = fetchResult.firstObject {
            return try await resolvePhotosAsset(phAsset: phAsset, result: result)
        }
    }
    
    // Fallback to file-based (camera capture, etc.)
    if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        // Still copy file (needed for playback), but don't create AVAsset here
        let url = try await loadMovieURL(from: result)
        // Get duration from PHAsset if available, else defer to background
        let duration = await getMetadataDuration(for: result) ?? 0
        return .video(url: url, duration: duration, assetIdentifier: result.assetIdentifier)
    }
    
    // ... image handling unchanged ...
}
```

---

### Diff 2: Remove Fallback AVAsset Duration Checks

**Files:**
- `TapesStore.swift:464` (buildClip)
- `TapesStore.swift:746` (insertMedia)
- `TapesStore.swift:799` (insertAtCenter)
- `TapesStore.swift:859` (insertAtCenter variant)
- `TapeCardView.swift:367` (makeClips)

**Change:** Remove `if clip.duration <= 0 { AVURLAsset(...) }` fallbacks. Accept duration from picker or PHAsset metadata. Defer to background if missing.

---

### Diff 3: Replace `generateThumbAndDuration` with PHImageManager Request

**File:** `TapesStore.swift:951`

**Change:**
```swift
func requestThumbnailOnly(for clipID: UUID, assetLocalId: String, targetSize: CGSize, tapeID: UUID) {
    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
    guard let asset = fetchResult.firstObject else { return }
    
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = false  // ✅ Timeline only - no network
    options.deliveryMode = .opportunistic
    options.resizeMode = .fast
    
    PHImageManager.default().requestImage(
        for: asset,
        targetSize: targetSize,
        contentMode: .aspectFill,
        options: options
    ) { image, info in
        guard let image = image else { return }
        Task { @MainActor in
            self.updateClip(clipID, transform: { 
                $0.thumbnail = image.jpegData(compressionQuality: 0.8)
            }, in: tapeID)
        }
    }
}
```

**Call Sites Update:**
- `TapesStore.swift:435` - Call `requestThumbnailOnly` instead of `generateThumbAndDuration` for Photos assets
- For local files, still use `generateThumbAndDuration` (needed for camera captures)

---

### Diff 4: Update `regenerateMetadataFromPhotoLibrary` to Use Thumbnails Only

**File:** `TapesStore.swift:1087`

**Change:** Replace `requestAVAsset` with `requestImage` for thumbnails. Use `PHAsset.duration` directly (no AVAsset).

```swift
private func regenerateMetadataFromPhotoLibrary(assetLocalId: String, clipID: UUID, tapeID: UUID) {
    let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
    guard let asset = fetch.firstObject else { return }

    if asset.mediaType == .image {
        Task { @MainActor in
            self.updateClip(clipID, transform: { clip in
                clip.duration = Tokens.Timing.photoDefaultDuration
                clip.updatedAt = Date()
            }, in: tapeID)
        }
        
        // Request thumbnail only
        requestThumbnailOnly(for: clipID, assetLocalId: assetLocalId, targetSize: CGSize(width: 400, height: 400), tapeID: tapeID)
        return
    }

    // For videos: Use PHAsset.duration (no AVAsset)
    Task { @MainActor in
        self.updateClip(clipID, transform: { clip in
            clip.duration = asset.duration  // ✅ Direct from PHAsset
            clip.updatedAt = Date()
        }, in: tapeID)
    }
    
    // Request thumbnail only (no AVAsset)
    requestThumbnailOnly(for: clipID, assetLocalId: assetLocalId, targetSize: CGSize(width: 400, height: 400), tapeID: tapeID)
}
```

---

### Diff 5: Implement Thumbnail Caching/Preheating

**New File:** `Tapes/Platform/Photos/TimelineThumbnailProvider.swift`

**Responsibilities:**
- Manage `PHCachingImageManager` instance
- Track visible clip indices
- Preheat thumbnails for visible + adjacent clips
- Cancel requests for off-screen clips
- Request thumbnails on-demand with proper options

**Integration:** Call from `ClipCarousel` or `TapeCardView` based on scroll position.

---

## Risk Assessment

### Risk 1: HEIF/Live Photos Thumbnail Quality
- **Impact:** Medium
- **Mitigation:** Test with various HEIF/Live Photos. `requestImage` should handle automatically.
- **Fallback:** Accept slightly lower quality thumbnails if needed for speed.

### Risk 2: Edited Assets Orientation
- **Impact:** Low
- **Mitigation:** `requestImage` respects `PHAsset.imageData` orientation. Test with rotated/edited assets.
- **Validation:** Compare thumbnails from `requestImage` vs current approach.

### Risk 3: Local File Duration Unknown
- **Impact:** Low
- **Mitigation:** Accept duration = 0 initially for local files. Defer to background generation when clip selected for playback.
- **UX:** Duration badge shows "0:00" until resolved (acceptable).

### Risk 4: Photos Asset Metadata Missing
- **Impact:** Low
- **Mitigation:** `PHAsset` properties are always available (no network needed). Duration may be 0 for images (use default).

### Risk 5: Thumbnail Cache Memory
- **Impact:** Low
- **Mitigation:** Use small target size (carousel cell × 2), limit preheat window (visible + 2 adjacent), cancel off-screen requests promptly.

---

## Testing Strategy

### Unit Tests
1. `resolvePickedMedia` - No AVAsset created for Photos assets
2. `requestThumbnailOnly` - Thumbnail requested with `isNetworkAccessAllowed = false`
3. Metadata extraction from PHAsset (duration, dimensions)

### Integration Tests
1. Add Photos video to tape - Verify no AVAsset created, no network requests
2. Add Photos image to tape - Verify thumbnail loads, metadata extracted
3. Scroll carousel - Verify preheat/cancel working
4. Add local file (camera) - Verify file still copied (needed for playback)

### Manual QA
1. **Timeline Performance:** Add 50+ clips, verify fast rendering
2. **Memory:** Monitor memory during large tape creation
3. **Network:** Verify no network activity when adding Photos assets (Airplane mode)
4. **Playback:** Verify playback still works (defers AVAsset resolution correctly)

---

## Instrumentation (Debug Only)

### Logging to Add

**In `resolvePickedMedia`:**
```
[INTAKE] asset=\(assetID) type=\(mediaType) duration=\(duration)s size=\(width)x\(height) source=\(photos|file) network=\(false)
```

**In `requestThumbnailOnly`:**
```
[THUMB] asset=\(assetID) targetSize=\(width)x\(height) network=\(false) cached=\(true|false)
```

**Guard Clauses (Detect Eager Resolution):**
- Log warning if `AVURLAsset` created during intake
- Log warning if `requestAVAsset` called with `isNetworkAccessAllowed = true` during intake
- Log warning if file copy happens for Photos assets (shouldn't happen)

---

## Migration Notes

### Backward Compatibility
- Existing `Clip` model remains unchanged (JSON compatibility)
- `localURL` may be `nil` for Photos assets (OK - playback uses `assetLocalId`)
- `duration` may be 0 initially for local files (resolved in background)

### Rollout Strategy
1. **Phase 1:** Implement thumbnail-only requests, keep existing duration fallbacks (gradual transition)
2. **Phase 2:** Remove duration fallbacks, defer to background
3. **Phase 3:** Add preheat/cancel for carousel optimization

---

## Summary of Changes

### Files to Modify
1. `Tapes/Platform/Photos/MediaProviderLoader.swift` - Remove AVAsset from `resolvePickedMedia`
2. `Tapes/ViewModels/TapesStore.swift` - Remove AVAsset fallbacks, add thumbnail-only requests
3. `Tapes/Views/TapeCardView.swift` - Remove AVAsset fallback in `makeClips`
4. `Tapes/Features/Import/PhotoImportCoordinator.swift` - Update to use PHImageManager

### Files to Create
1. `Tapes/Platform/Photos/TimelineThumbnailProvider.swift` - Thumbnail caching/preheating service

### Files Unchanged (Deferral Already Working)
1. `Tapes/Playback/TapeCompositionBuilder.swift` - Already defers AVAsset to playback ✅
2. `Tapes/Export/TapeExporter.swift` - Already defers AVAsset to export ✅

---

## Acceptance Criteria

✅ **COMPLETED** - All criteria met:

✅ **Verified via logs:** Adding assets to Tape does not:
- Create `AVURLAsset` instances ✅
- Call `requestAVAsset` with network access ✅
- Trigger file copies for Photos assets (only local files) ✅

✅ **Timeline Performance:** 
- 50+ clips render rapidly (**incredibly fast** - immediate thumbnail display) ✅
- Memory stays bounded (thumbnails only, no full asset loading) ✅

✅ **Playback/Export:**
- Still resolves AVAsset when needed (existing paths work) ✅
- Network access enabled only during playback/export ✅

✅ **Additional Optimisations:**
- Retina-quality thumbnails (automatic @2×/@3× scaling) ✅
- `.fastFormat` delivery mode for immediate returns ✅
- Single-callback pattern (no degraded/progressive loading) ✅

---

## Implementation Complete

**See:** [`docs/features/TimelineAssetIntakeOptimization.md`](./features/TimelineAssetIntakeOptimization.md) for full implementation details, data flow, and technical documentation.

**Key Achievements:**
1. ✅ `TimelineThumbnailProvider` created with PHCachingImageManager
2. ✅ `resolvePickedMedia` uses PHAsset metadata (no AVAsset)
3. ✅ All AVAsset fallbacks removed from intake paths (5 locations)
4. ✅ Instrumentation logging added (DEBUG only)
5. ✅ Retina scaling and `.fastFormat` for optimal performance
6. ✅ Continuation misuse fixed (single resume guard)

**Files Changed:**
- Created: `Tapes/Platform/Photos/TimelineThumbnailProvider.swift`
- Modified: `MediaProviderLoader.swift`, `TapesStore.swift`, `TapeCardView.swift`, `PhotoImportCoordinator.swift`, `CameraCoordinator.swift`

