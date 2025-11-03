# Timeline Asset Intake Optimization

## Summary

Optimised asset intake pipeline to load only thumbnails and metadata for timeline/carousel display, deferring full `AVAsset` resolution and iCloud downloads to playback/export.

**Impact:** Timeline builds **incredibly fast** with high-quality Retina thumbnails. Zero AVAsset creation, zero iCloud network access during intake.

## Purpose & Scope

### Problem
Previously, adding Photos assets to a Tape would:
- Eagerly create `AVAsset` instances
- Trigger iCloud downloads (`requestAVAsset` with network access)
- Copy full video files to temp directories
- Block timeline rendering while waiting for downloads

### Solution
New intake pipeline:
- Requests thumbnails only via `PHImageManager.requestImage()` 
- Uses `PHAsset` metadata directly (duration, pixel dimensions)
- **No network access** (`isNetworkAccessAllowed = false`)
- **No AVAsset creation** - uses `assetLocalId` only
- Retina-quality thumbnails with automatic scaling

## Key Components

### 1. `TimelineThumbnailProvider.swift` (New)
- Manages `PHCachingImageManager` for thumbnail requests
- Provides preheating for visible clips
- No network access, local thumbnails only

### 2. `MediaProviderLoader.swift` - `resolvePhotosAsset()`
- Detects Photos assets by `assetIdentifier`
- For videos: Returns `PickedMedia.video(url: nil, duration: phAsset.duration, assetIdentifier: ...)`
- For images: Requests thumbnail via `PHImageManager` (no full image load)
- **No file copying, no AVAsset creation**

### 3. `TapesStore.swift` - `requestThumbnailOnly()`
- Requests thumbnails with Retina scaling
- Uses `.fastFormat` delivery mode for immediate returns
- Updates clip thumbnail asynchronously

### 4. Updated `PickedMedia` Enum
```swift
case video(url: URL?, duration: TimeInterval, assetIdentifier: String?)
// url is nil for Photos assets - no local file copy
```

### 5. `Clip` Model
- Photos videos: `localURL = nil`, `assetLocalId = <Photos identifier>`
- Thumbnails loaded via `requestThumbnailOnly()` in background

## Data Flow

### Intake Path (Picker → Timeline)

```
PHPickerResult
  ↓
resolvePickedMedia() [MediaProviderLoader]
  ├─ resolvePhotosAsset() [if assetIdentifier exists]
  │   ├─ PHAsset.fetchAssets() → metadata
  │   ├─ requestPhotosThumbnail() → UIImage (Retina, no network)
  │   └─ return PickedMedia (url: nil for Photos assets)
  └─ buildClip() [TapesStore]
      ├─ Clip.fromVideo() [local files only]
      ├─ Clip(assetLocalId, localURL: nil) [Photos videos]
      └─ requestThumbnailOnly() [background async]
          └─ PHImageManager.requestImage() [.fastFormat, Retina scale]
```

### Playback Path (Timeline → Player)

```
TapeCompositionBuilder.loadAssets()
  ├─ For Photos assets (localURL == nil, assetLocalId exists):
  │   └─ PHImageManager.requestAVAsset() [isNetworkAccessAllowed = true]
  └─ Resolve AVAsset only when needed for playback
```

## Technical Details

### Thumbnail Quality
- **Display Size:** 150×84 points (carousel cell size)
- **Retina Scaling:** Automatically applies `UIScreen.main.scale` (2× or 3×)
- **Final Size:** 300×168 @2× or 450×252 @3× pixels
- **JPEG Quality:** 0.85

### Delivery Mode: `.fastFormat`
- **Returns immediately** with cached thumbnails
- **No degraded callback cycle** (single callback)
- **Fastest possible** - no progressive loading

### Network Policy
```swift
options.isNetworkAccessAllowed = false  // ✅ Timeline intake
options.isNetworkAccessAllowed = true   // ✅ Playback/export only
```

### Performance Optimisations

1. **Parallel Requests:** Multiple thumbnails load concurrently
2. **Caching:** `PHCachingImageManager` preheats visible range
3. **No File I/O:** Photos assets don't copy files (no `localURL`)
4. **Metadata Direct:** `PHAsset.duration` used directly (no AVAsset needed)

## Files Changed

### Created
- `Tapes/Platform/Photos/TimelineThumbnailProvider.swift`

### Modified
- `Tapes/Platform/Photos/MediaProviderLoader.swift`
  - Added `resolvePhotosAsset()` 
  - Added `requestPhotosThumbnail()` with Retina scaling
  - Updated `PickedMedia.video` to allow `url: nil`

- `Tapes/ViewModels/TapesStore.swift`
  - Removed 5 locations with AVAsset fallbacks
  - Added `requestThumbnailOnly()` with Retina scaling
  - Updated `buildClip()`, `insertMedia()`, `insertAtCenter()`, `insert()`
  - Updated `regenerateMetadataFromPhotoLibrary()` to use PHAsset directly

- `Tapes/Views/TapeCardView.swift`
  - Removed AVAsset fallback from `makeClips()`

- `Tapes/Features/Import/PhotoImportCoordinator.swift`
  - Added `resolvePhotosAsset()` using PHAsset metadata
  - Removed AVAsset creation for Photos assets

- `Tapes/Features/Camera/CameraCoordinator.swift`
  - Added guard for optional `url` in `PickedMedia.video`

## Testing & QA Considerations

### Verification Checklist
- ✅ Adding Photos assets to Tape doesn't trigger iCloud downloads
- ✅ Timeline renders thumbnails rapidly (no blocking)
- ✅ Memory stays bounded (no full asset loading)
- ✅ Playback/export still works (AVAsset resolved on-demand)
- ✅ Retina thumbnails display crisp (300×168 @2× minimum)
- ✅ Camera captures still work (local files have `url`)

### Logging (DEBUG only)
- `[INTAKE]` - Asset intake with metadata (type, duration, size, source)
- `[THUMB]` - Thumbnail request (target size, scale, cached status)

### Edge Cases Handled
- Photos videos with `url: nil` - handled gracefully
- Missing `assetIdentifier` - falls back to file-based handling
- Thumbnail request failures - returns `nil`, clip still created
- Continuation misuse - guards against multiple resumes

## Related Tickets/Links

- Original audit: `docs/TimelineAssetIntake_Audit.md`
- Performance goal: Match video loading speed for image intake

## Notes

- Timeline thumbnails are **display-only** - full resolution not needed
- Playback pipeline (`TapeCompositionBuilder`) handles AVAsset resolution separately
- Export pipeline uses same deferred resolution pattern
- This optimisation **does not affect** playback/export quality or functionality

