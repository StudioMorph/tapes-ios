# Cursor Bootstrap — Tapes iOS (SwiftUI)

You are an expert iOS engineer. Follow this plan step‑by‑step to scaffold and implement the TAPES MVP using SwiftUI + AVFoundation. Work **task by task** and keep PR-sized commits.

## Project constraints
- Platform: **iOS 16+**, Swift 5.9+, **SwiftUI**.
- Bundle id: **com.studiomorph.Tapes**.
- Keep code modular: `Models/`, `Views/`, `ViewModels/`, `Services/`, `Export/`, `Components/`, `Theme/`.
- Use native frameworks only (no 3rd‑party deps).

---

## 1) Design System (Theme/)
Create a light/dark aware design system.

**Files**
- `Theme/Colors.swift`
- `Theme/Typography.swift`
- `Theme/Spacing.swift`
- `Theme/Tokens.swift` (exports typed accessors)

**Colours**
- Background: dark `#0B0B0F`, light `#FFFFFF`
- Card: dark `#121520`, light `#F5F7FB`
- TextPrimary: dark `#FFFFFF`, light `#0B0B0F`
- AccentRed: dark `#E53935`, light `#D32F2F`
- MutedGrey: `#8A94A6`

**Typography**
- Headline 24/28 semibold
- Title 18/24 semibold
- Body 16/22 regular
- Caption 12/16 regular

**Spacing & Radius**
- 4,8,12,16,20,24; radius: 12 (cards), 20 (sheets), full (FAB)

**Acceptance**
- Provide `ColorTheme` and `TextStyle` helpers usable from any View.
- Add Preview demonstrating dark/light variants.

---

## 2) Core Models (Models/)
Create data models and enums.

```swift
struct Tape: Identifiable, Hashable {
    var id: UUID
    var title: String
    var orientation: Orientation // .portrait / .landscape
    var scaleMode: ScaleMode     // .fit / .fill
    var transition: TransitionStyle // .none / .crossfade / .slideLR / .slideRL / .randomise
    var transitionDuration: Double  // seconds
    var clips: [Clip]
}

struct Clip: Identifiable, Hashable {
    var id: UUID
    var assetLocalId: String // PHAsset localIdentifier
}

enum Orientation { case portrait, landscape }
enum ScaleMode { case fit, fill }
enum TransitionStyle { case none, crossfade, slideLR, slideRL, randomise }
```

Add `SampleData` with a blank tape for previews.

---

## 3) App Structure & Navigation
Bottom bar with three tabs: **Recent**, **Spaces** (placeholder), **Account** (placeholder).

- `Views/Root/AppRootView.swift`
- `Views/Tapes/TapesListView.swift`
- `ViewModels/TapesStore.swift` (in‑memory for MVP)

**TapesListView**
- Lists tapes as cards.
- Each card embeds the **timeline carousel** (see step 4).
- Right‑side controls row: Settings (gear), Cast (AirPlay overlay only when available), Play (▶︎ sheet).

---

## 4) Timeline Carousel with Fixed‑Center FAB
Implement the main interaction exactly as specified:

- FAB (red, camera icon) **fixed at the center** of the tape card.
- Thumbnails (16:9, width = `(screenWidth - 64)/2`) form a **horizontal carousel** that **snaps** such that **one item sits on each side** of the fixed FAB.
- There is a **start “+” placeholder** at index 0 and a **tail “+”** at the end when at least one clip exists.

**Behaviour**
- Swiping the carousel moves **thumbnails**, not the FAB.
- Insertion position = the **gap under the FAB** (between left and right items).
- Long‑press + upward flick on a clip → delete confirmation. If result is empty → keep **only** the start “+”.

**Files**
- `Components/ClipThumbnail.swift`
- `Components/ClipCarousel.swift` (snap math + insertion index publishing)
- `Components/RecordFAB.swift` (swipe‑to‑change mode: Camera → Gallery → Transition)

**Acceptance**
- Provide unit for snap calculation: given scroll offset + item width → returns leftIndex/rightIndex & insertionIndex.
- Haptic on snap.

---

## 5) Clip Edit Sheet
`Components/ClipEditSheet.swift` bottom sheet with:
- **Trim** (opens native editor via `PhotosUI`/`UINavigationController` wrapper)
- **Rotate 90°** (store flag per clip; apply in preview/export transforms)
- **Fit / Fill** (per‑clip override)
- **Share…** (stub)
- **Remove** (with confirm)

---

## 6) Tape Settings Sheet (Global)
`Components/TapeSettingsSheet.swift` with:
- Orientation: Portrait / Landscape
- Conflicting aspect ratios: Fit / Fill
- Transitions: None, Crossfade, Slide (L→R), Slide (R→L), Randomise
- Duration slider: 0.2–1.0s (but **Randomise clamps to 0.5s**)

Changes apply live to preview.

---

## 7) Preview Player
`Views/Player/TapePlayerView.swift`:
- Plays the tape with visual transitions matching settings.
- Respect per‑clip rotate + fit/fill.
- AirPlay overlay button (only visible when devices available) — we’ll integrate after step 9.

---

## 8) Export (hook to stubs we already have)
Wire the exporter entry point so the UI can export:

- Add `Export/TapeExporter.swift` (use the provided file from our Runbook package; includes **slides + audio crossfades** + Photos album save).
- Provide `Export/TransitionPicker.swift` (seeded per‑tape sequence + duration clamp = 0.5s for Randomise).

UI:
- Play button opens action sheet: **Preview Tape** / **Merge & Save**.
- On export: show progress HUD; on success show Photos sheet / toast.

---

## 9) AirPlay Button (conditional)
- Add `Services/CastManager.swift` (polls `AVRouteDetector` every ~10s).
- `Components/AirPlayButton.swift` wraps `AVRoutePickerView`.
- Render only when `hasAvailableDevices == true`.

---

## 10) Permissions
Add to `Info.plist` (strings provided):
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`

---

## 11) Acceptance Criteria (MVP)
- Carousel **snaps** so one item is on each side of fixed FAB.
- Inserting from **Camera**/**Gallery** places the new clip **exactly under the FAB** (between left/right).
- **Start “+”** shown when empty; after deletions back to empty → only start “+” remains.
- Global transitions apply to all boundaries unless **Randomise** is selected (seeded).
- Preview and Export show the **same transition sequence**.
- iOS export produces **1080p** MP4 in Photos › “Tapes” album with **video slide/crossfade + audio fade**.

---

## 12) Suggested file tree

```
Tapes/
  Models/
  ViewModels/
  Views/
    Root/
    Tapes/
    Player/
  Components/
  Services/
  Export/
  Theme/
```

---

## Work plan
1) Theme + Tokens → 2) Models → 3) Root nav → 4) Carousel+FAB → 5) Edit Sheet → 6) Settings → 7) Player → 8) Export → 9) AirPlay → 10) Polish.

Create small, incremental commits and keep Types/Props documented with comments.
