# iOS Cursor Context (SwiftUI • AVFoundation)

> Pin this in Cursor as a project-level context so the agent understands your native Apple environment and coding conventions for this repo.

---

## Target Stack & Tooling
- **Platform:** iOS 17+  
- **Xcode:** 16+  
- **Swift:** 5.10+  
- **UI Framework:** **SwiftUI** first; use UIKit only for bridging when strictly necessary  
- **Architecture:** MVVM with modular features  
- **Dependencies:** **Swift Package Manager only** (no CocoaPods)  
- **Persistence:** JSON via `FileManager` initially; pluggable to Core Data later  
- **Concurrency:** Swift Concurrency (`async/await`, `Task`, `@MainActor`)  
- **Networking:** `URLSession` + `Codable`  
- **Media:** **AVFoundation** for video/audio, **Photos** for library access  
- **Location/Maps:** `CoreLocation`, `MapKit` (if needed later)  

**Authoritative Docs**  
- Swift language: https://docs.swift.org/swift-book/  
- Xcode (latest): https://developer.apple.com/xcode/  
- iOS SDK: https://developer.apple.com/documentation/  
- SwiftUI: https://developer.apple.com/documentation/swiftui  
- Combine: https://developer.apple.com/documentation/combine  
- Concurrency: https://developer.apple.com/documentation/swift/swift_standard_library/concurrency  
- URLSession: https://developer.apple.com/documentation/foundation/urlsession  
- Codable: https://developer.apple.com/documentation/swift/codable  
- AVFoundation: https://developer.apple.com/documentation/avfoundation  
- Photos framework: https://developer.apple.com/documentation/photokit  
- CoreLocation: https://developer.apple.com/documentation/corelocation  
- MapKit: https://developer.apple.com/documentation/mapkit  
- Keychain Services: https://developer.apple.com/documentation/security/keychain_services  
- Human Interface Guidelines (HIG): https://developer.apple.com/design/human-interface-guidelines/  
- App Intents: https://developer.apple.com/documentation/appintents  
- WidgetKit: https://developer.apple.com/documentation/widgetkit  
- ActivityKit (Live Activities): https://developer.apple.com/documentation/activitykit  

---

## Project Conventions (Tapes)
- **Modules**
  - `App/Features/Tape/…` (feature-specific UI & view models)
  - `Core/Models` (e.g., `Tape`, `Clip`, `TapeItemID`)
  - `Core/Persistence` (JSON now, pluggable for Core Data later)
  - `Core/Media` (AVAsset utilities, durations, export)
  - `Core/Thumbnails` (generation + cache)
  - `Core/Logging` (unified logger)
  - `DesignSystem/` (shared UI components)
- **No singletons** where avoidable; prefer constructor injection or environment objects scoped to features.
- **Testing:** Unit + UI tests under `Tests/` with clear naming.
- **Error handling:** Prefer typed errors + `Result` or `throws`; surface user-safe messages.

---

## SwiftUI Rules of the Road
- Use `NavigationStack`, `.sheet`, `.popover`, `.confirmationDialog` appropriately.
- State flow: `@State` (local), `@ObservedObject` (child), `@StateObject` (owner), `@EnvironmentObject` (global app state sparingly).
- **Animations:** `withAnimation { … }`, `matchedGeometryEffect`, `.transition(_:)`. Default to subtle durations (≈0.2–0.4s) consistent with HIG.
- **Layout:** Prefer modern stacks, `Grid`, and `ScrollView`. Avoid hard-coded sizes where possible. Support Dynamic Type.
- **Async images/video thumbnails:** use task modifiers; keep UI updates on `@MainActor`.

Useful SwiftUI references:  
- NavigationStack: https://developer.apple.com/documentation/swiftui/navigationstack  
- matchedGeometryEffect: https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:isSource:properties:anchor:isActive:)  
- Presentation APIs: https://developer.apple.com/documentation/swiftui/presentation  

---

## AVFoundation Guidance (Tapes)
- **Thumbnails:** generate with `AVAssetImageGenerator`; cache to disk.
- **Playback:** `AVPlayer` + `AVPlayerLayer`/`VideoPlayer` (SwiftUI) for previews.
- **Editing:** build `AVMutableComposition` with tracks; apply transitions via `AVMutableVideoComposition` + Core Animation tool or opacity/transform ramps.
- **Export:** `AVAssetExportSession` (H.264, 1080p) to Photos using `PHPhotoLibrary`.
- **Audio:** Keep original sequential audio; no multi-track mixing for MVP.

Useful AVFoundation references:  
- AVAsset & tracks: https://developer.apple.com/documentation/avfoundation/avasset  
- AVMutableComposition: https://developer.apple.com/documentation/avfoundation/avmutablecomposition  
- AVMutableVideoComposition: https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition  
- AVAssetExportSession: https://developer.apple.com/documentation/avfoundation/avassetexportsession  
- PHPhotoLibrary save: https://developer.apple.com/documentation/photokit/phphotolibrary

---

## Concurrency & Threading
- Prefer `async/await` and `Task` over callbacks. Use `Task.detached` sparingly.
- UI-affecting work must be annotated with `@MainActor`.
- Heavy exports/thumbnailing: run off the main actor using structured concurrency.

References:  
- Concurrency overview: https://developer.apple.com/documentation/swift/swift_standard_library/concurrency  
- MainActor: https://developer.apple.com/documentation/swift/mainactor

---

## Permissions & Privacy
- **Photos:** Use `PHPhotoLibrary.requestAuthorization`.  
- **Camera/Microphone:** `AVCaptureDevice` permissions if recording is added.  
- **Location:** Only if enabling geo features; request the minimal necessary level.
- Ensure matching keys in **Info.plist**; do not access without a usage description.

Docs:  
- Photo authorization: https://developer.apple.com/documentation/photokit/requesting_authorization_to_photos_data  
- AVCapture authorization: https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/requesting_authorization_for_media_capture_on_apple_platforms  
- Location authorization: https://developer.apple.com/documentation/corelocation/choosing_the_authorization_level_for_location_services

---

## Security & Storage
- Use **Keychain** for tokens/secrets.  
- Use `FileManager` + app sandbox for media cache.  
- Avoid storing PII in logs.

Docs:  
- Keychain: https://developer.apple.com/documentation/security/keychain_services  
- FileManager: https://developer.apple.com/documentation/foundation/filemanager

---

## Coding Style & Quality
- Follow Swift API Design Guidelines: https://www.swift.org/documentation/api-design-guidelines/  
- Prefer small, composable views and view models.  
- Document non-obvious decisions with doc comments.  
- Add unit tests for media utilities and export logic.

---

## Nice-to-Haves for Cursor
- When suggesting third-party libraries, **first prefer native Apple APIs**. If native is insufficient, propose SPM-compatible dependencies with rationale.
- Provide **runnable code**: include imports, minimal models, and mock data where needed.
- Suggest **HIG-compliant** UI and motion.

---

## Project Structure (expected)
```
TapesApp/
├─ App/
│  └─ Features/
│     └─ Tape/
│        ├─ Title/
│        ├─ Timeline/
│        │  ├─ Left placeholder/
│        │  ├─ Clip/
│        │  ├─ Right placeholder/
│        │  ├─ Capture/
│        │  ├─ Library/
│        │  └─ Fab/
│        ├─ Tape settings/
│        ├─ Merge and download/
│        ├─ Play tape/
│        └─ Air play/
├─ Core/
│  ├─ Models/
│  ├─ Persistence/
│  ├─ Media/
│  ├─ Thumbnails/
│  └─ Logging/
├─ DesignSystem/
└─ Tests/
   ├─ Unit/
   └─ UI/
```

---

## Snippets Cursor Can Reuse
**Export 1080p MP4 (H.264) skeleton**
```swift
func export(composition: AVMutableComposition,
            videoComposition: AVVideoComposition,
            to url: URL) async throws {
  guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
    throw ExportError.unavailable
  }
  export.videoComposition = videoComposition
  export.outputURL = url
  export.outputFileType = .mp4
  try await export.export()
}
```

**Generate thumbnail at 25% duration**
```swift
func thumbnail(for asset: AVAsset) async throws -> UIImage {
  let gen = AVAssetImageGenerator(asset: asset)
  gen.appliesPreferredTrackTransform = true
  let duration = try await asset.load(.duration)
  let time = CMTimeMultiplyByFloat64(duration, multiplier: 0.25)
  let cg = try gen.copyCGImage(at: time, actualTime: nil)
  return UIImage(cgImage: cg)
}
```

---

## Non‑Goals for MVP
- No filters/stickers/text overlays  
- No multi-track audio mixing  
- No cloud sync  
- No per-junction transition customisation beyond None/Crossfade/Slide (L↔R)  

---

## When in Doubt
- Prefer first-party APIs, align with HIG, and keep exports/playback smooth at 1080p.  
- Provide reasons for deviating from these rules (performance, capability, or UX constraints).

