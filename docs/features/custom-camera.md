# Custom Camera (AVCaptureSession)

## Summary

Replaces `UIImagePickerController` with a custom `AVCaptureSession`-based camera that mirrors the iOS 26 Apple Camera app. It delivers instant startup on multi-lens iPhones and adds features unavailable via the system picker: zoom presets with virtual-lens switchover, tap-to-focus with continuous refocus, Live Photo capture, a self-timer, multi-capture with a session review carousel, and orientation-correct capture while the UI stays locked to portrait.

## Purpose & Scope

`UIImagePickerController` caused multi-second freezes on devices with triple/dual-wide camera systems while it negotiated lens configuration internally. Moving to `AVCaptureSession` eliminates that delay and gives us full control over capture behaviour and UI. The custom camera is used from both **My Tapes** and **Shared Tapes** (collaborative contributions) via the same `CameraCoordinator` entry point.

Native Apple APIs are used throughout: `AVFoundation` for capture, `PhotosUI` / `PHPhotoLibrary` for saving, `CoreMotion` for device orientation, and SwiftUI with `NavigationStack` + toolbars for the shell.

## Architecture

- **`CaptureService`** (`Tapes/Features/Camera/CaptureService.swift`)
  - Owns `AVCaptureSession`, video + audio `AVCaptureDeviceInput`, `AVCapturePhotoOutput`, and a dynamically attached `AVCaptureMovieFileOutput` for video recording.
  - Publishes session state: `captureMode`, `flashMode`, `isLivePhotoEnabled`, `timerDelay`, `torchEnabled`, `currentZoomFactor`, `availableZoomPresets`, `isRecording`, `recordingDuration`, `capturedItems`, `capturedCount`, `videoRotationAngle`.
  - Defines `CaptureMode` (`.photo` / `.video`), `TimerDelay` (`.off` / `.three` / `.ten`), and `ZoomPreset` (id, label, factor).
  - Implements `AVCapturePhotoCaptureDelegate` and `AVCaptureFileOutputRecordingDelegate`.

- **`CameraView`** (`Tapes/Features/Camera/CameraView.swift`)
  - SwiftUI shell wrapped in a `NavigationStack` with native toolbar items.
  - Hosts `CameraPreviewView` (a `UIViewRepresentable` over `AVCaptureVideoPreviewLayer`) and all overlays: zoom pill, mode picker, shutter, flip button, thumbnail preview, Done button, focus square, countdown, shutter-flash, recording badge, and the session review carousel.
  - Contains `DeviceOrientationObserver`, a `CMMotionManager`-backed `ObservableObject` that publishes `iconRotation: Angle` (for UI counter-rotation) and `videoRotationAngle: CGFloat` (for capture connections).

- **`CameraCoordinator`** (`Tapes/Features/Camera/CameraCoordinator.swift`)
  - Handles camera permission prompts and presentation.
  - Saves captured items to the Photos library on Done: `PHAssetChangeRequest` for regular photos/videos, `PHAssetCreationRequest` with `.photo` + `.pairedVideo` resources for Live Photos. Returns `[PickedMedia]` with each item's `assetLocalIdentifier` to the caller.

- **`AppDelegate`** (`Tapes/AppDelegate.swift`)
  - Exposes `static var orientationLock: UIInterfaceOrientationMask` and returns it from `application(_:supportedInterfaceOrientationsFor:)`, allowing `CameraView` to lock the interface to portrait while the rest of the app keeps its default mask.

## UI Layout

Top to bottom, matching the iOS 26 Apple Camera app:

- **Navigation bar** (`NavigationStack` + `ToolbarItem`):
  - Leading: `xmark` close button.
  - Principal: recording badge when recording (red dot + elapsed time in a material capsule).
  - Trailing: **photo mode** — `ellipsis` button that expands the options tray (flash, Live Photo, timer). **Video mode** — a single flash toggle (no ellipsis tray).
- **Viewfinder**: full-screen `AVCaptureVideoPreviewLayer`, edge-to-edge.
- **Overlays on the viewfinder**:
  - **Zoom pill** — material capsule with `.5`, `1`, `2` presets; the active preset is highlighted yellow. Pinch-to-zoom is also supported and ramps via `ramp(toVideoZoomFactor:withRate:)`.
  - **Focus square** — yellow animated rectangle at the tap location.
  - **Countdown overlay** — large numeral when `timerDelay` is active.
  - **Shutter flash** — black `Color` overlay briefly animated on `willCapturePhotoFor` for tactile feedback.
- **Bottom stack**:
  - **Mode picker** — VIDEO / PHOTO (video default).
  - **Row** (left → right): **thumbnail preview** with multi-capture count badge, **shutter**, and **flip camera** button. The flip button sits horizontally centred between the shutter and the right edge, vertically aligned with the shutter, on an `.ultraThinMaterial` circular background. The **Done** button appears in place of the thumbnail label when there are captured items.

### Orientation behaviour

The interface stays locked to portrait (via `AppDelegate.orientationLock`). `DeviceOrientationObserver` reads the accelerometer and applies `.rotationEffect(iconRotation)` **only** to: the close button, the flash / ellipsis icon, each zoom pill label, the flip button icon, and the thumbnail image. The rest of the UI, gradients, and safe-area treatment remain fixed. `videoRotationAngle` is pushed to the photo and movie output connections so captured stills and videos are correctly oriented regardless of how the phone is held.

## Capture Modes & Options Tray

| Mode | Tray | Controls |
|---|---|---|
| Photo | `ellipsis` opens bottom tray | Flash (off / auto / on), Live Photo (when supported), Timer (off / 3s / 10s) |
| Video | No tray | Flash toggle only (acts as torch during recording) |

Live Photo and Timer are disabled on devices or configurations where they are not supported; the UI reflects the disabled state.

## Zoom

Uses `virtualDeviceSwitchOverVideoZoomFactors` to map the physical lens switchover points to user-facing labels:

| User label | Raw `videoZoomFactor` | Physical lens |
|---|---|---|
| `.5` | 1.0 | Ultra-wide |
| `1` | switchOver[0] (typically 2.0) | Wide |
| `2` | switchOver[0] × 2 (typically 4.0) | Digital zoom toward telephoto |

The camera starts at the "1x" (wide lens) zoom factor. The `.5` preset is only published when an ultra-wide is present on the active device.

## Focus & Exposure

- **At session start and after `switchCamera()`** the device is configured for `focusMode = .continuousAutoFocus`, `exposureMode = .continuousAutoExposure`, the points of interest are recentred to `(0.5, 0.5)`, and `isSubjectAreaChangeMonitoringEnabled` is set to `true`.
- **Tap-to-focus** does a one-shot `.autoFocus` / `.autoExpose` at the tapped point and keeps subject-area monitoring on.
- **Subject-area change notifications** (`AVCaptureDeviceSubjectAreaDidChange`) trigger `configureContinuousAutoFocus(device:)` again, so the camera automatically reverts to continuous AF/AE as soon as the scene composition changes. The observer is rebound on every camera switch and removed in `deinit`.
- The focus-square overlay uses the screen tap location reported by `CameraPreviewView`, independent of the device focus point, so it renders exactly where the user tapped (no mirror offset for the front camera).

## Live Photo Pipeline

1. When Live Photo is enabled, `applyModeOutputs(for: .photo)` attaches a temporary `AVCaptureMovieFileOutput` so the photo output can emit a companion movie.
2. `capturePhoto()` issues `AVCapturePhotoSettings` with a `livePhotoMovieFileURL`.
3. `photoOutput(_:willCapturePhotoFor:)` fires the shutter-flash immediately for instant UI feedback.
4. `photoOutput(_:didFinishProcessingPhoto:)` stores the still image + its `fileDataRepresentation()` in a `pendingLivePhotos` buffer keyed by the settings id, and appends a still-only `PickedMedia.photo` to `capturedItems` so the thumbnail count updates right away.
5. When the companion movie arrives via `photoOutput(_:didFinishProcessingLivePhotoToMovieFileAt:...)`, the corresponding `capturedItems` entry is replaced with a full `PickedMedia.photo(image:assetIdentifier:isLivePhoto: true, imageData:, livePhotoMovieURL:)`.
6. On Done, `CameraCoordinator.performSave()` saves Live Photos with `PHAssetCreationRequest` adding both a `.photo` resource (from `imageData`) and a `.pairedVideo` resource (from `livePhotoMovieURL`, with `shouldMoveFile = true`). The returned `placeholderForCreatedAsset.localIdentifier` is attached to the outgoing `PickedMedia`.

`PickedMedia.photo` now carries `isLivePhoto`, `imageData`, and `livePhotoMovieURL` end-to-end, and downstream code (`TapesStore`, `TapeCardView`, `MediaImportCoordinator`) pattern-matches on those fields to persist the Live Photo flag on the `Clip` model.

## Timer

`TimerDelay` is a small enum (`off`, `three`, `ten`) with a `next` rotator used by the timer toolbar button. When non-zero and in photo mode, tapping the shutter starts a countdown overlay; the actual capture is issued at t = 0. Rotating or backgrounding during the countdown cancels it.

## Multi-Capture & Session Review Carousel

- `CaptureService.capturedItems` accumulates every successful capture; `capturedCount` drives the thumbnail's badge.
- Tapping the thumbnail sets `showCarousel = true`, which presents a full-screen overlay:
  - Background: `Rectangle().fill(.ultraThinMaterial)` over the viewfinder; the camera toolbar and close button are hidden.
  - A native-style top bar with a **Done** button styled the same way as the camera's Done button (`.ultraThinMaterial` capsule).
  - Horizontal `ScrollView` centred vertically at `geo.size.height / 2` high, with 32 pt spacing between items. Item height is recalculated on rotation.
  - Each item renders at the correct aspect ratio (videos use a pre-built thumbnail), with a 44×44 delete button whose centre sits on the top-right corner of the thumbnail. Deleting calls `CaptureService.removeItem(at:)`.
  - Video thumbnails are built once on open into `videoThumbnailCache: [URL: UIImage]` using `AVAssetImageGenerator`, preventing the previous flicker from repeated regeneration.
  - The `ScrollView` height is `itemHeight + 56` with `.padding(.vertical, 28)` so the delete buttons never clip at the top.

## Shutter Feedback

`photoOutput(_:willCapturePhotoFor:)` posts `onShutterFired` to the main queue. `CameraView` toggles a `shutterFlash` state that briefly shows a black `Color` overlay with a quick `easeIn` / `easeOut` animation, mirroring Apple's fade-out shutter effect.

## Data Flow

```
AVCaptureSession (CaptureService)
        │ capturedItems: [PickedMedia]
        ▼
CameraView (Done tap)
        ▼
CameraCoordinator.performSave()
        │ PHAssetChangeRequest / PHAssetCreationRequest
        ▼
Photos library → assetLocalIdentifier
        ▼
[PickedMedia] (with assetLocalIdentifier, isLivePhoto, etc.)
        ▼
Caller (TapesStore for My Tapes, SharedTapesView for contributions)
```

## Related Files

- `Tapes/Features/Camera/CaptureService.swift`
- `Tapes/Features/Camera/CameraView.swift` (contains `CameraPreviewView` and `DeviceOrientationObserver`)
- `Tapes/Features/Camera/CameraCoordinator.swift`
- `Tapes/AppDelegate.swift` (interface orientation lock hook)
- `Tapes/Platform/Photos/MediaProviderLoader.swift` (`PickedMedia` enum)
- `Tapes/ViewModels/TapesStore.swift` (`PickedMedia` pattern matching for Live Photos)

## Testing / QA Considerations

- **Devices**: verify on triple-camera (Pro), dual-wide, and single-camera iPhones; confirm the `.5` preset only appears when an ultra-wide is present.
- **Startup**: camera presents without the multi-second freeze that `UIImagePickerController` produced on multi-lens devices.
- **Zoom**: pinch and the zoom pill both ramp smoothly across lens switchovers; `1x` is the default.
- **Focus**: scene composition changes cause the camera to refocus without user input; a tap focuses on that exact point and then returns to continuous AF after the scene changes.
- **Exposure**: both continuous and tap-to-expose behave as above.
- **Torch**: toggles reliably during active video recording (video mode flash = torch).
- **Live Photo**: toggle appears only in photo mode on supported devices, saved photos show a Live Photo indicator in the Photos app and animate on 3D-touch / long-press, and the tape clip is persisted with `isLivePhoto = true`.
- **Timer**: 3s and 10s countdowns fire correctly; cancellation on dismiss / rotation works.
- **Orientation**: device rotation rotates only the close button, flash / ellipsis icon, zoom pill labels, flip button icon, and thumbnail image; everything else (layout, safe-area gradients) stays put. Stills and videos shot while the phone is in landscape open in landscape in Photos and in the tape.
- **Shutter flash**: a quick fade is visible on every still capture, including Live Photos.
- **Multi-capture**: count badge increments; Done returns all items as a single `[PickedMedia]`.
- **Session review carousel**: half-screen height, 32 pt spacing, aspect ratios preserved; delete button centred on the top-right corner of each thumbnail and never clipped; video thumbnails do not flicker; Done button styled as the camera's Done; layout recalculates on rotation.
- **Permissions**: first-run camera + microphone + Photos prompts are handled by `CameraCoordinator`.

## Related Tickets / Docs

- `docs/features/LivePhotos.md` — downstream Live Photo handling in the player / tape store.
- `docs/features/MediaImportOverlay.md` — alternate entry point used by picker-based imports.
- `docs/features/Phase3-CollaborativeTapes.md` — camera is also the contribution entry point for collaborative tapes.
