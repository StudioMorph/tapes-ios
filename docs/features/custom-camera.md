# Custom Camera (AVCaptureSession)

Replaces `UIImagePickerController` with a custom `AVCaptureSession`-based camera to eliminate startup delays on multi-lens iPhones and provide full control over the capture experience.

## Purpose & Scope

The native `UIImagePickerController` caused multi-second freezes on devices with triple/dual-wide camera systems while it negotiated lens configuration internally. A custom `AVCaptureSession` camera resolves this and enables features unavailable through the system picker: pinch-to-zoom, tap-to-focus, Live Photo capture, torch control during recording, and multi-capture (batch recording of several clips before returning).

## Key UI Components

- **CameraView** — Full-screen SwiftUI camera interface with Apple Camera-inspired layout.
  - Top toolbar with close button, chevron trigger for options tray, and torch indicator.
  - Options tray (slides in from bottom of toolbar area): flash/torch toggle, Live Photo toggle.
  - Zoom pill: `.5x`, `1x`, `2x` presets in a dark capsule, with the active preset highlighted in yellow.
  - Mode picker: VIDEO / PHOTO (video default).
  - Shutter button: white ring + white fill (photo) or red fill/square (video record/stop).
  - Thumbnail preview with multi-capture count badge.
  - Done button (glass material, blue text) replaces the flip-camera button when captures exist.
  - Focus square: yellow animated rectangle on tap-to-focus.
  - Recording badge: red dot + elapsed time in a glass capsule.

- **CameraPreviewView** — `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`. Reports both the device focus point and the screen tap location for accurate focus-square placement.

## Data Flow

`CameraView` owns a `@StateObject CaptureService` for session management and a `@ObservedObject CameraCoordinator` for permission handling and Photos library saving.

1. **Capture**: `CaptureService` manages `AVCaptureSession`, `AVCapturePhotoOutput`, `AVCaptureMovieFileOutput`.
2. **Multi-capture**: Captured items accumulate in `CaptureService.capturedItems` as `PickedMedia` values.
3. **Done**: User taps Done → `CameraCoordinator.handleMultiCapture(_:)` saves all items to the Photos library via `PHAssetChangeRequest`, then returns `[PickedMedia]` with `assetLocalIdentifier` to the calling view's completion handler.

## Zoom Implementation

Uses `virtualDeviceSwitchOverVideoZoomFactors` to map physical lens switchover points to user-facing labels:

| User label | Raw `videoZoomFactor` | Physical lens |
|---|---|---|
| .5x | 1.0 | Ultra-wide |
| 1x | switchOver[0] (typically 2.0) | Wide |
| 2x | switchOver[0] × 2 (typically 4.0) | Digital zoom / approaching telephoto |

The camera defaults to the "1x" (wide lens) zoom factor on startup.

## Related Files

- `Tapes/Features/Camera/CaptureService.swift`
- `Tapes/Features/Camera/CameraView.swift`
- `Tapes/Features/Camera/CameraCoordinator.swift`
- `Tapes/Platform/Photos/MediaProviderLoader.swift` (`PickedMedia` enum)

## Testing / QA Considerations

- Verify on triple-camera (Pro), dual-camera, and single-camera devices.
- Confirm `.5x` preset only appears on devices with an ultra-wide lens.
- Confirm torch toggles reliably during active video recording.
- Confirm Live Photo toggle appears only in photo mode on supported devices.
- Verify focus square appears at the exact tap location, not mirrored.
- Confirm multi-capture count badge increments correctly and Done returns all items.
