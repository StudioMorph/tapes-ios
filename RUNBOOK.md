
# TAPES (REELZ) — MVP Runbook

This document is the **single source of truth** for building the TAPES MVP.
It consolidates the previously split `RUNBOOK_v2.md` and `RUNBOOK_v2_MASTER.md`
into a single runbook.

Structure: **Design Tokens → Components → Screen Layouts → User Flows → Technical Rules → Build → QA → Cloud Sharing → Future**.

---

## 1. Design Tokens (Light/Dark)

- **Colours**
  - Primary Red: #E50914 (Root spec) / Red 600–700 variants (Docs spec)
  - Secondary Gray: #222
  - Surface: `#0B0B0F` dark / `#FFFFFF` light
  - On-Surface: `#FFFFFF` dark / `#0B0B0F` light
  - Muted: grayscale ramp (8–96)

- **Typography**
  - Heading / Headline: 20–24pt, Semibold/Bold (SF Pro / Roboto)
  - Title: 17/24, Semibold
  - Body: 16pt Regular
  - Caption: 12pt Regular

- **Spacing & Shape**
  - Spacing scale: 4, 8, 12, 16, 20, 24, 32
  - Radius: 12 (cards), 20 (sheets), full (FAB), 8 (thumbnails)

- **Mode**
  - Support both Light and Dark mode

---

## 2. Components

- **FAB (Record/Swipe-to-Snap)**
  - States: Camera, Add from Gallery, Transition
  - Swipe left/right to cycle modes
  - Red circular button, fixed center in carousel

- **Thumbnail Carousel**
  - Aspect: 16:9
  - Width: `(screenWidth - 64)/2`
  - Snap so one item sits left and one right of FAB
  - Shows index label (`TapeName/pos:N`)
  - Start/end placeholders: "+"

- **Media Import Positioning**
  - **Red FAB (center)**: Insert clips at red line position using "between index" system
    - Red line corresponds to 0-based "between index" p ∈ [0…N] where N = clips.count
    - If red line is before first clip → p = 0 (insert at start)
    - If red line is between clip i and clip i+1 → p = i+1 (insert between them)
    - If red line is after last clip → p = N (insert at end)
    - Position is snapshotted when picker opens to handle user scrolling
  - **Left "+" placeholder**: Always insert at index 0 (start of timeline)
  - **Right "+" placeholder**: Always insert at index clips.count (end of timeline)
  - **Selection order**: Preserved for multi-select imports
  - **Array insertion**: Clips are inserted at the exact "between index" in the timeline array

- **Clip Edit Sheet**
  - Actions: Trim (native), Rotate 90°, Fit/Fill, Share/AirDrop, Remove (confirm)

- **Tape Settings Sheet (Global)**
  - Orientation: Portrait (9:16) or Landscape (16:9)
  - Conflicting Ratios: Fill / Fit
  - Transition: None / Crossfade / Slide L→R / Slide R→L / Randomise
  - Transition Duration: 0.2–1.0s (Randomise clamp ≤ 0.5s)

- **Player Controls**
  - Restart, Play/Pause, Clip index
  - Play button → full-screen player (preview only). Merge & Save only via tape card arrow.down.

- **Cast Button**
  - iOS: AVRoutePickerView (AirPlayButton) — visible only if devices available
  - Android: CastButton stub — toast if no devices

- **Custom Camera** (see `docs/features/custom-camera.md`)
  - `AVCaptureSession`-based capture with native iOS 26 look and feel (NavigationStack + toolbars).
  - Features: `.5`/`1`/`2` zoom presets with virtual-lens switchover, pinch-to-zoom, tap-to-focus with continuous subject-area refocus, Live Photo, self-timer (3s / 10s), multi-capture + session review carousel, shutter flash, torch, portrait-locked UI with selective icon counter-rotation.

---

## 3. Screen Layouts

- **Timeline Screen (Tape Builder)**
  - Top: Title, Settings (gear), AirPlay button if available
  - Middle: Player canvas (orientation-driven), overlay controls
  - Bottom: Carousel with fixed FAB
  - Edit Sheet + Settings Sheet (modal)

- **Clip Edit Tray**
  - Tap thumbnail → Tray
  - Options: Trim, Rotate, Fit/Fill, Delete

- **Tape Settings**
  - Global orientation, transitions, aspect, duration

- **Player**
  - Preview playback with transitions (WYSIWYG)
  - Play opens player; Merge & Save via card arrow.down only

---

## 4. User Flows

1. **Create Tape**
   - Launch → new tape with "+" placeholders
   - FAB inserts clip

2. **Insert Clip**
   - Carousel snaps → insert at center
   - Options: Record or Add from device

3. **Edit Clip**
   - Tap → tray → Trim, Rotate, Fit/Fill, Delete

4. **Set Transitions**
   - Global setting; Randomise uses Tape UUID seed, clamped duration

5. **Preview**
   - ▶️ → Preview tape with transitions

6. **Export**
   - ▶️ → Merge & Save
   - iOS: AVFoundation composition, 2 video+audio tracks with crossfade + audio ramps
   - Android: FFmpegKit, 1080p scaled/padded, xfade + acrossfade

7. **Cast**
   - iOS: AirPlayButton shows if devices exist
   - Android: CastButton toast placeholder

8. **Share & Collaborate** (see §8 Cloud Sharing)
   - Share a tape → recipients resolve the link → clips download from R2 into Photos → tape appears in Shared tab.
   - Collaborative contributions route through the Custom Camera or media picker back into the recipient's copy.

---

## 5. Technical Rules

- **Storage Model**
  - App = UI layer only; clips remain in Photos / MediaStore
  - Temp export inputs only
  - Shared / downloaded assets are saved into the Photos library and linked via `PHAsset.localIdentifier` so R2 assets can be deleted safely

- **Timeline Asset Loading**
  - Tape creation uses lightweight clip metadata and thumbnails only.
  - Full AVAsset composition/rendering is deferred to preview playback.

- **Persistence & Responsiveness**
  - Tape JSON persistence is debounced and runs off the main thread.
  - Playback teardown must avoid blocking the main thread.
  - Image-to-video preparation uses async completion rather than blocking waits.

- **Snapping / Insertion**
  - FAB fixed; carousel snaps around it
  - New clip inserts between left and right neighbour
  - **Carousel Position Management**: Single source of truth with proper ordering
    - Skip initial position when `pendingTargetItemIndex` exists
    - Monotonic UUID token system prevents stale applies
    - Scope isolation by `tape.id` prevents cross-talk
    - Layout gating: only apply when `contentSize.width > 0 && bounds.width > 0`
    - `isProgrammaticScroll` flag prevents feedback loops / double-advancement

- **Aspect Ratio**
  - Global orientation sets canvas
  - Per-clip Fit/Fill overrides global

- **Randomise Transitions**
  - Deterministic (Tape UUID as seed)
  - Clamp ≤ 0.5s

- **Export Implementation**
  - iOS: `TapeExportSession` (class) wraps `TapeCompositionBuilder.buildExportComposition(for:)` with background music, HEVC encoding via `AVAssetReader` / `AVAssetWriter`, and save to Photos.
    - `ExportCoordinator` manages lifecycle: progress polling, ETA, cancellation, completion sound + haptics, local notifications, and HIG-inspired custom dialogs.
    - On iOS 26+, exports use `BGContinuedProcessingTask` to continue in the background with a system Live Activity showing progress; a real notification fires on actual completion.
    - Header shows circular progress ring when dialog is dismissed.
    - Single entry point: tape card arrow.down.
  - Android: FFmpegKit filtergraph (xfade + acrossfade), 1080p scaled / padded.

- **Preview Composition (iOS)**
  - Preview playback uses per-clip `AVPlayerItem` instances via `TapePlayerViewModel` (MVVM).
  - Transitions are applied at runtime (crossfade / slide) using a two-player slot architecture.
  - Clips are preloaded sequentially with an LRU cache (10 entries, evicts on memory warning).
  - Global timeline scrubber seeks across the entire tape; scrubbing navigates between clips automatically.
  - Photo clips use a custom `AVVideoCompositing` pipeline (`StillImageVideoCompositor`) for real-time Ken Burns.
  - `AVAudioSession` configured as `.playback` with interruption and route-change handling.
  - Reduce Motion: slide transitions become crossfade; Ken Burns motion is disabled.
  - Export and non-preview flows still resolve `.image` clips by synthesising a short H.264 asset.
  - Photo assets are normalised for EXIF orientation; frames clamp to ≤ 1920×1080.
  - Builder split into 3 files: core (`TapeCompositionBuilder`), asset resolution (`+AssetResolution`), image encoding (`+ImageEncoding`).

- **First-Content → Insert Top Empty Tape**
  - **Goal**: When first media is added to an empty tape, create a new empty tape at the top.
  - **Implementation**:
    - `Tape` model: persistent `hasReceivedFirstContent: Bool`
    - `TapesStore`: `insertEmptyTapeAtTop()` and `restoreEmptyTapeInvariant()`
    - `TapeCardView`: `checkAndCreateEmptyTapeIfNeeded()` side effect
  - **Behaviour**: first import into empty tape → media lands in viewed tape → new empty tape appears at index 0 → selection remains on original tape.

---

## 6. Build & Dependencies

### iOS

- **Frameworks**: AVFoundation, Photos, PhotosUI, AVKit, UserNotifications, AudioToolbox, BackgroundTasks, CoreMotion
- **Export**: AVAssetReader / AVAssetWriter with HEVC encoding; `BGContinuedProcessingTask` (iOS 26+) for background export
- **Minimum target**: iOS 18.2, Xcode 16+, Swift 5.0
- **Dependency management**: Swift Package Manager only
- **Key files**
  - **Player**
    - `Tapes/Views/Player/TapePlayerView.swift` (thin View shell)
    - `Tapes/Views/Player/TapePlayerViewModel.swift` (playback state + logic)
    - `Tapes/Components/AirPlayButton.swift` (AVRoutePickerView wrapper)
    - `Tapes/Components/Player*.swift` (Header, Controls, ProgressBar, LoadingOverlay, SkipToast)
  - **Playback / Composition**
    - `Tapes/Playback/TapeCompositionBuilder.swift`
    - `Tapes/Playback/TapeCompositionBuilder+AssetResolution.swift`
    - `Tapes/Playback/TapeCompositionBuilder+ImageEncoding.swift`
    - `Tapes/Playback/StillImageVideoCompositor.swift`
    - `Tapes/Playback/AsyncSemaphore.swift`
  - **Export**
    - `Tapes/Export/TapeExporter.swift` (`TapeExportSession`)
    - `Tapes/Export/ExportCoordinator.swift`
    - `Tapes/Export/ExportDialogs.swift` (CircularProgressRing, ExportProgressDialog, ExportCompletionDialog, ExportErrorAlert)
    - `Tapes/Export/iOSExporterBridge.swift` (async bridge to `TapeExportSession`)
  - **Custom Camera**
    - `Tapes/Features/Camera/CaptureService.swift`
    - `Tapes/Features/Camera/CameraView.swift` (contains `CameraPreviewView` and `DeviceOrientationObserver`)
    - `Tapes/Features/Camera/CameraCoordinator.swift`
    - `Tapes/AppDelegate.swift` (`orientationLock` hook)
  - **Cloud Sharing** (see §8)
    - `Tapes/Core/Auth/AuthManager.swift`
    - `Tapes/Core/Networking/TapesAPIClient.swift`
    - `Tapes/Core/Networking/ShareUploadCoordinator.swift`
    - `Tapes/Views/Share/ShareFlowView.swift`, `Tapes/Views/Share/SharedTapesView.swift`
    - `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift`
    - `Tapes/Core/Navigation/NavigationCoordinator.swift`
  - **Design System**
    - `Tapes/DesignSystem/**` — prefer these components over ad-hoc SwiftUI views in new screens.
- **Info.plist**
  - `BGTaskSchedulerPermittedIdentifiers` configured in the project-root plist (array-type keys require a physical plist file, not `INFOPLIST_KEY_` build settings).
  - Camera / microphone / Photos usage descriptions.
- **Entitlements**: Associated Domains (`applinks:`), Push Notifications.

### Android

- **Dependencies**
  ```gradle
  implementation "com.arthenica:ffmpeg-kit-full:6.0-2"
  ```
- Media3 Transformer (concat fallback)
- **Files**
  - `android/TransitionPicker.kt`
  - `android/TapeExporter.kt`
  - `android/TapeExporter_FFmpeg.kt`
  - `android/TapeExporterMedia3Concat.kt`
  - `android/CastManager.kt`
  - `android/CastButton.kt`

---

## 7. QA

- Use `qa/QA_SmokeTest_Checklist.md`
- Validate:
  - Snapping correctness
  - Transition parity (preview vs export)
  - Export destinations
  - Casting visibility
  - Custom Camera: continuous autofocus, tap-to-focus, Live Photo save in Photos app, timer, orientation, multi-capture, carousel delete + Done
  - Cloud sharing: share-link open → download → tape appears in Shared tab; contribution flow for collaborative tapes
- Run automated composition tests before release:
  ```bash
  xcodebuild -project Tapes.xcodeproj \
             -scheme TapesTests \
             -sdk iphonesimulator \
             -configuration Debug test
  ```
- Debugging tips
  - Enable `AVPlayerItem` logging: inspect `player.currentItem?.videoComposition` for instruction ranges.
  - For audio ramps, dump `audioMix?.inputParameters` and ensure ramps align with video overlap.
  - Inject a custom `assetResolver` to log clip IDs / URLs when investigating asset issues.

---

## 8. Cloud Sharing (Active)

### Dependencies

- **Cloudflare Workers** backend at `tapes-api.hi-7d5.workers.dev`
- **Cloudflare R2** bucket `tapes-media` for clip storage
- **Cloudflare D1** database `tapes-db` for metadata
- **APNs** for push notifications (new invites, new contributions)
- **Sign in with Apple** for user identity
- **Universal Links** configured via `apple-app-site-association` on the share domain

### Key Modules

- `Tapes/Core/Auth/AuthManager.swift` — Apple ID auth + server JWT exchange
- `Tapes/Core/Networking/TapesAPIClient.swift` — API contract (tapes, clips, collaborators, shares, manifest)
- `Tapes/Core/Networking/ShareUploadCoordinator.swift` — background upload coordinator (progress overlay, completion dialogs)
- `Tapes/Views/Share/ShareFlowView.swift` — sender share flow (uploads clips to R2)
- `Tapes/Views/Share/SharedTapesView.swift` — Shared tab (renders real `TapeCardView` components)
- `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift` — recipient download + tape builder (writes assets into Photos library + tape-specific album)
- `Tapes/Core/Navigation/NavigationCoordinator.swift` — deep link handling

### Recipient Flow

1. User opens share link → app resolves share ID → downloads clips from R2 (presigned GET URLs).
2. Progress overlay shown (identical to import from photo picker).
3. Assets are saved to the Photos library and associated with a per-tape album (`"[Tape Name]"` for view-only, `"[Tape Name] - Collab"` for collaborative duplicates).
4. A real `Tape` with `ShareInfo` metadata is created and persisted locally, linked by `PHAsset.localIdentifier`.
5. Tape appears in the "Shared" tab as a normal tape card.

### Collaborative Tapes

- When a tape is shared collaboratively, the owner's original tape in "My Tapes" stays untouched; a duplicate is forked into the "Shared with Me" tab and is the one that receives contributions and syncs.
- Contributions (new clips + creative settings such as motion style, image duration, rotation, scale-mode override) are uploaded via `ShareUploadCoordinator` and merged into the forked tape on the owner's device.
- APNs notifications fire on new invites and new contributions (topic: `StudioMorph.Tapes`).

### Configuration

- Cloudflare secrets managed via `wrangler secret put` (JWT_SECRET, R2 credentials, `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`)
- Backend deployed via `wrangler deploy` from `tapes-api/`
- D1 migrations live in `tapes-api/migrations/` and are applied via `wrangler d1 migrations apply tapes-db`
- iOS entitlements: Associated Domains (`applinks:`), Push Notifications

---

## 9. Future (Post-MVP)

- Per-clip transitions
- Filters & text overlays
- Full Cast integration
- Real-time collaborative tape editing
- Cross-platform share targets

---

# End of Runbook
