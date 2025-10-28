# TAPES Code Review Report

## Executive Score (1–100)
- **Score:** 41/100
- The core editing and playback engine shows thoughtful design, but critical reliability and privacy defects undermine baseline usability: imported videos are lost after a restart, transitions selected by the user are ignored in exports, and persistence runs on the main thread while serialising full-resolution media into an unprotected JSON file. Accessibility, tooling, and limited-platform support debt compound the risk for an App Store launch.

## Score Breakdown
| Category | Weight | Score | Notes |
| --- | --- | --- | --- |
| Architecture & Modularity | 15 | 6 | `TapesStore` concentrates persistence, album sync, and UI state; feature flags hard-code destructive behaviour. |
| Code Quality & Swift Best Practices | 15 | 7 | Modern SwiftUI used in places, but legacy constructs (`NavigationView`, `ActionSheet`, extensive prints) and duplication indicate drift. |
| Concurrency & Thread Safety | 10 | 6 | Structured concurrency adopted sporadically; several `Task.detached` blocks lack lifetime management. |
| Performance & Energy | 10 | 4 | Main-thread file I/O, repeated image decoding, and polling timers present avoidable jank and battery drain. |
| Reliability & Testing | 10 | 3 | Media imports are ephemeral, transition settings do not export correctly, and automated coverage barely touches the surface. |
| Security & Privacy | 10 | 3 | Photo clips are stored as raw bytes in Documents, duplicating personal media without protection. |
| Accessibility & Internationalisation | 10 | 4 | Primary controls are gesture-driven `Image` views without semantics; text and layouts ignore Dynamic Type. |
| iOS HIG Compliance | 10 | 5 | The visual language is coherent, yet several screens rely on deprecated navigation and fixed sizing that break in compact or split layouts. |
| App Store Review Guideline Risks | 5 | 2 | Limited Photos permission flows and data handling gaps risk guideline 5.1.1 scrutiny. |
| Tooling, CI/CD & Maintainability | 5 | 1 | No static analysis, formatting, or CI automation is present. |

## Project Overview
- **Tech stack:** Swift 5, SwiftUI + UIKit bridges, AVFoundation, Photos/PhotosUI, os.log, Swift Concurrency.
- **Major modules:** `Tapes` (UI and view models), `DesignSystem`, `Components`, `Playback`, `Export`, `Platform/Photos`, `Features` (Camera, Import, MediaPicker).
- **Third-party dependencies:** None (no CocoaPods/SPM/Carthage references).
- **Build targets:** `Tapes` (app), `TapesTests`, `TapesUITests` inside `Tapes.xcodeproj`.
- **Minimum iOS version:** 18.2 (IPHONEOS_DEPLOYMENT_TARGET in all configurations).
- **Capabilities/entitlements:** None defined; runtime permissions rely on generated Info.plist strings for Camera, Microphone, and Photos access.

## Strengths
- `Tapes/Playback/TapeCompositionBuilder.swift:126` – Async timeline generation cleanly composes render metadata per clip and transition.
- `Tapes/Playback/PlaybackPreparationCoordinator.swift:64` – Warm-up pipeline with retry/back-off prepares playback incrementally while handling skips.
- `Tapes/Platform/Photos/TapeAlbumService.swift:55` – Photos integration neatly reuses or recreates albums with async permission handling and fallbacks.
- `TapesTests/TapeCompositionBuilderTests.swift:9` – Export builder tests cover crossfade, slide, image handling, and stress edge cases with generated assets.

## Findings & Issues (Prioritised)

### Critical
1. **Temporary imports cleared between launches break saved tapes**  
   - **Severity:** Critical  
   - **Category:** Reliability & Testing  
   - **Location:** `Tapes/Platform/Photos/MediaProviderLoader.swift:43`  
   - **Evidence:**
     ```swift
     // copy to tmp/Imports then persist the URL
     let importsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
     let dest = importsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
     try FileManager.default.copyItem(at: src, to: dest)
     ```
     `Clip` instances store that `dest` via `Clip.fromVideo`, and `saveTapesToDisk()` persists the URL.  
   - **Impact:** iOS purges `tmp` across restarts or under storage pressure, leaving clips pointing to missing files; playback, editing, and export fail silently for any imported video.  
   - **Likelihood:** High (system routinely cleans Temporary on reboot/background).  
   - **Recommendation:** Move media into `Application Support` (see `moveToPersistentStorage` helper), track migrations for existing tapes, and validate file existence at load time with fallback UI.  
   - **Effort:** M

### High
1. **Exports ignore tape transition settings**  
   - **Severity:** High  
   - **Category:** Reliability & Testing  
   - **Location:** `Tapes/Export/TapeExporter.swift:25`  
   - **Evidence:**
     ```swift
     // Simple transition - no complex picker needed
     let seq: [TransitionStyle] = Array(repeating: .crossfade, count: max(0, tape.clips.count - 1))
     ```
   - **Impact:** Users selecting slide/random transitions see the correct preview but receive crossfaded renders, breaking expectations and App Store metadata promises.  
   - **Likelihood:** High (affects every export).  
   - **Recommendation:** Map `tape.transition` (and per-clip overrides if introduced) to `TransitionStyle`, honour `.none`, and update tests to assert export output metadata.  
   - **Effort:** M

2. **Auto-save performs synchronous JSON I/O on the main actor**  
   - **Severity:** High  
   - **Category:** Performance & Energy  
   - **Location:** `Tapes/ViewModels/TapesStore.swift:975`  
   - **Evidence:**
     ```swift
     let data = try JSONEncoder().encode(sanitized)
     try data.write(to: persistenceURL) // executes on the MainActor
     ```
     paired with `loadTapesFromDisk()` calling `Data(contentsOf:)` in the `@MainActor` init.  
   - **Impact:** As clip counts grow, main-thread writes and reads block user input, risk watchdog terminations, and drain energy (especially when `autoSave()` is called after every mutation).  
   - **Likelihood:** High (triggered by every clip change).  
   - **Recommendation:** Offload encoding and disk writes to a dedicated persistence actor/queue, batch saves, and adopt atomic file replacement with background `URLSession`.  
   - **Effort:** M

3. **Photo clips persisted as raw base64 in Documents**  
   - **Severity:** High  
   - **Category:** Security & Privacy  
   - **Location:** `Tapes/Models/Clip.swift:16`  
   - **Evidence:**
     ```swift
     public var imageData: Data? // encoded into tapes.json alongside thumbnails
     ```
   - **Impact:** Full-resolution user photos and generated thumbnails are duplicated into `Documents/tapes.json`, unencrypted and backed up, potentially breaching user expectations and App Store guideline 5.1.1 about data minimisation.  
   - **Likelihood:** High (every imported photo takes this path).  
   - **Recommendation:** Persist only asset identifiers or move binary blobs to a protected container (`FileProtectionType.complete`), with explicit user disclosure and deletion tooling.  
   - **Effort:** M

4. **Primary tape controls lack accessible button semantics**  
   - **Severity:** High  
   - **Category:** Accessibility & Internationalisation  
   - **Location:** `Tapes/Views/TapeCardView.swift:148`  
   - **Evidence:**
     ```swift
     Image(systemName: "gearshape")
         .font(.system(size: 17, weight: .semibold))
         .onTapGesture { onSettings() }
     ```
   - **Impact:** VoiceOver users cannot discover or activate key actions, and the 17pt glyphs fall short of the 44pt hit target guidance.  
   - **Likelihood:** High (applies to every card control).  
   - **Recommendation:** Use `Button` with `Label`, add `.accessibilityLabel`/`.accessibilityHint`, enforce 44pt tappable frames, and provide focus order.  
   - **Effort:** S

### Medium
1. **Carousel layout tied to `UIScreen` width**  
   - **Severity:** Medium  
   - **Category:** iOS HIG Compliance  
   - **Location:** `Tapes/Views/TapeCardView.swift:182`  
   - **Evidence:**
     ```swift
     let screenW = UIScreen.main.bounds.width
     let availableWidth = max(0, screenW - Tokens.FAB.size)
     let thumbW = floor(availableWidth / 2.0)
     ```
   - **Impact:** On iPad, Stage Manager, or split-view the carousel mis-sizes thumbnails and FAB positioning, violating adaptive layout guidance.  
   - **Likelihood:** Medium (any multi-window context).  
   - **Recommendation:** Drive sizing from `GeometryReader` and size classes, and add layout tests for compact/regular combinations.  
   - **Effort:** M

2. **Feature flag enforces album deletion despite comment**  
   - **Severity:** Medium  
   - **Category:** Architecture & Modularity  
   - **Location:** `Tapes/ViewModels/FeatureFlags.swift:6`  
   - **Evidence:**
     ```swift
     static var deleteAssociatedPhotoAlbum: Bool {
         return true // comment states default should be false
     }
     ```
   - **Impact:** Every tape deletion attempts to delete the Photos album, requiring read-write access and risking unexpected data loss or repeated permission prompts.  
   - **Likelihood:** High.  
   - **Recommendation:** Externalise feature toggles (e.g., build settings, remote config) and default to false until UX, permissions, and migration paths are vetted.  
   - **Effort:** S

3. **Thumbnail rendering decodes image data per frame**  
   - **Severity:** Medium  
   - **Category:** Performance & Energy  
   - **Location:** `Tapes/Models/Clip.swift:203`  
   - **Evidence:**
     ```swift
     public var thumbnailImage: UIImage? {
         guard let thumbnailData = thumbnail else { return nil }
         return UIImage(data: thumbnailData)
     }
     ```
   - **Impact:** SwiftUI recomposition repeatedly inflates JPEG data into `UIImage`, spiking CPU and memory during scrolling.  
   - **Likelihood:** High (every gallery render).  
   - **Recommendation:** Cache decoded thumbnails (e.g., `ImageCache` or disk-based) and limit stored size (pre-generate 320px JPEGs).  
   - **Effort:** M

4. **Limited Photos permission flow risks rejection**  
   - **Severity:** Medium  
   - **Category:** App Store Review Guideline Risks  
   - **Location:** `Tapes/ViewModels/TapesStore.swift:1163`  
   - **Evidence:**
     ```swift
     guard FeatureFlags.deleteAssociatedPhotoAlbum,
           let albumId = tape.albumLocalIdentifier else { return }
     Task.detached { try await self?.albumService.deleteAlbum(withLocalIdentifier: albumId) }
     ```
     `deleteAlbum` escalates to `.readWrite` even when the app previously asked for `.addOnly`.  
   - **Impact:** Users with limited Photos access receive repeated failures with no in-app path to upgrade, conflicting with App Review 5.1.1 (respect limited access & provide management UI).  
   - **Likelihood:** Medium.  
   - **Recommendation:** Detect limited status, surface `PHPhotoLibrary.presentLimitedLibraryPicker`, gate album deletion behind explicit consent, and update copy to reflect constraints.  
   - **Effort:** M

5. **Automated coverage does not exercise core workflows**  
   - **Severity:** Medium  
   - **Category:** Reliability & Testing  
   - **Location:** `TapesTests/TapesTests.swift:13`  
   - **Evidence:**
     ```swift
     @Test func example() async throws {
         // Write your test here...
     }
     ```
   - **Impact:** Persistence, album synchronisation, importer timeout, and exporter regressions ship untested.  
   - **Likelihood:** High (no tests exist for these flows).  
   - **Recommendation:** Add unit tests for `TapesStore` persistence/album queues, `MediaProviderLoader`, exporter transition mapping, and UI snapshot/UI tests for accessibility flows.  
   - **Effort:** M

6. **No linting or CI guardrails**  
   - **Severity:** Medium  
   - **Category:** Tooling, CI/CD & Maintainability  
   - **Location:** Repository root  
   - **Evidence:** Project contains no `.swiftlint.yml`, `.swiftformat`, or `.github/workflows` / `fastlane` automation.  
   - **Impact:** Style, static analysis, and regression tests rely on manual discipline; PRs cannot enforce minimum quality.  
   - **Likelihood:** High.  
   - **Recommendation:** Introduce SwiftLint/SwiftFormat configs, enable Xcode build warnings as errors, and add CI (Xcode Cloud, GitHub Actions) running unit/UI tests and static analysis.  
   - **Effort:** M

### Low
1. **Deprecated `ActionSheet` API**  
   - **Severity:** Low  
   - **Category:** iOS HIG Compliance  
   - **Location:** `Tapes/Views/TapesListView.swift:29`  
   - **Evidence:**
     ```swift
     .actionSheet(isPresented: $showingPlayOptions) { ActionSheet(...) }
     ```
   - **Impact:** On iPad the sheet anchors poorly; Apple now recommends `confirmationDialog`.  
   - **Likelihood:** Medium.  
   - **Recommendation:** Migrate to `.confirmationDialog` with `NavigationStack`.  
   - **Effort:** S

2. **AirPlay polling timer keeps firing indefinitely**  
   - **Severity:** Low  
   - **Category:** Performance & Energy  
   - **Location:** `Tapes/CastManager.swift:16`  
   - **Evidence:**
     ```swift
     timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
         self?.hasAvailableDevices = self?.detector.multipleRoutesDetected ?? false
     }
     ```
   - **Impact:** Polling every 10 seconds consumes energy and keeps the run loop alive even when casting is unused or the app backgrounds.  
   - **Likelihood:** Medium.  
   - **Recommendation:** Use `AVRouteDetector` delegate callbacks or `AVRoutePickerView`, and suspend detection when the UI disappears.  
   - **Effort:** S

3. **Detached task captures `self` strongly in metadata generation**  
   - **Severity:** Low  
   - **Category:** Concurrency & Thread Safety  
   - **Location:** `Tapes/ViewModels/TapesStore.swift:948`  
   - **Evidence:**
     ```swift
     private func processAssetMetadata(_ asset: AVAsset, clipID: UUID, tapeID: UUID) {
         Task.detached(priority: .utility) {
             let duration = try await asset.load(.duration)
             await MainActor.run { self.updateClip(...) }
         }
     }
     ```
   - **Impact:** Background tasks keep the store alive unnecessarily and can apply updates after deallocation/testing teardown.  
   - **Likelihood:** Low (store is long lived) but problematic for unit tests.  
   - **Recommendation:** Capture `[weak self]` or use `Task { ... }` on the main actor with `await`ed background work.  
   - **Effort:** S

## Suggested Improvements & Code Examples
- **Persist imported media safely:** move files into Application Support and guard against duplicates.
  ```swift
  func persistImport(at source: URL) throws -> URL {
      let supportDir = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
          .appendingPathComponent("Media", isDirectory: true)
      try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
      let destination = supportDir.appendingPathComponent(source.lastPathComponent)
      if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: source, to: destination)
      return destination
  }
  ```
- **Asynchronous persistence pipeline:** isolate disk I/O from the main actor.
  ```swift
  actor TapeStorePersistence {
      private let url: URL
      init(url: URL) { self.url = url }

      func save(_ tapes: [Tape]) async throws {
          let data = try JSONEncoder().encode(tapes)
          try data.write(to: url, options: .atomic)
      }
  }
  // Usage inside TapesStore
  try await persistence.save(tapes.map { $0.removingPlaceholders() })
  ```
- **Respect transition selection in exporter:** bridge `TransitionType` into `TransitionStyle`.
  ```swift
  let transitionSequence = tape.transition == .randomise
      ? tape.clips.indices.dropLast().map { _ in randomStyle() }
      : Array(repeating: tape.transition.toTransitionStyle, count: tape.clips.count - 1)
  ```
- **Accessibility-aligned controls:** replace gesture images with accessible buttons and hints.
  ```swift
  Button {
      onSettings()
  } label: {
      Label("Edit tape settings", systemImage: "gearshape")
          .labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
  }
  .accessibilityHint("Opens transition, orientation, and album options")
  ```
- **SwiftUI best practice for navigation/dialogues:** modernise deprecated APIs.
  ```swift
  NavigationStack {
      // ...
  }
  .confirmationDialog("Choose an action", isPresented: $showingPlayOptions, titleVisibility: .visible) {
      Button("Preview Tape") { play() }
      Button("Merge & Save") { export() }
  }
  ```
- **Media pipeline optimisation:** cache thumbnails and durations once.
  ```swift
  final class ThumbnailCache {
      static let shared = NSCache<NSString, UIImage>()
      func image(for clip: Clip) -> UIImage? {
          if let cached = shared.object(forKey: clip.id.uuidString as NSString) { return cached }
          guard let data = clip.thumbnail else { return nil }
          let image = UIImage(data: data)
          if let image { shared.setObject(image, forKey: clip.id.uuidString as NSString) }
          return image
      }
  }
  ```

## Compliance Checklist (Tick/✗)
| Area | Status | Notes |
| --- | --- | --- |
| HIG – Navigation | ✗ | `NavigationView` and `ActionSheet` remain; no large-title alternatives on iPad. |
| HIG – Controls & Hit Targets | ✗ | Glyph-only `Image` views handle taps without 44pt targets. |
| HIG – Spacing & Motion | ✓ | Consistent spacing tokens and restrained motion. |
| HIG – Typography & Colour | ✗ | Fixed-size fonts ignore Dynamic Type despite adequate contrast. |
| App Review – Data Handling | ✗ | Raw media duplication in Documents lacks explicit disclosure/controls. |
| App Review – Permissions Copy | ✓ | Camera/Microphone/Photo purpose strings are specific. |
| Accessibility – Labels & Traits | ✗ | Primary controls lack button roles and hints. |
| Accessibility – Dynamic Type & Focus | ✗ | Fonts hard-coded; no focus order management. |
| Privacy/Security – ATS/Transport | ✓ | Defaults maintained; no HTTP exceptions. |
| Energy/Performance – Background work | ✗ | Main-thread persistence and polling timers remain. |

## Metrics Snapshot
- **Files:** 36 Swift source files in `Tapes`, 3 in `TapesTests`, 2 in `TapesUITests`.
- **Approximate SLOC:** 6,982 non-comment Swift lines in app code; 292 in unit tests; 39 in UI tests.
- **UI frameworks:** ~64% of files import SwiftUI (23/36); ~17% import UIKit directly (6/36) with targeted bridges.
- **Public API surface:** ≈203 `public` declarations across models, services, and view models.
- **Top complexity hotspots (line count per function):**
  1. `createVideoAsset` – `Tapes/Playback/TapeCompositionBuilder.swift:935` (79 lines)
  2. `loadImage` – `Tapes/Platform/Photos/MediaProviderLoader.swift:64` (75)
  3. `renameAlbum` – `Tapes/Platform/Photos/TapeAlbumService.swift:134` (68)
  4. `insertAtCenter` – `Tapes/ViewModels/TapesStore.swift:778` (61)
  5. `insertMedia` – `Tapes/ViewModels/TapesStore.swift:719` (56)
  6. `performSave` – `Tapes/Features/Camera/CameraCoordinator.swift:83` (53)
  7. `preparePlayer` – `Tapes/Views/Player/TapePlayerView.swift:207` (48)
  8. `regenerateMetadataFromPhotoLibrary` – `Tapes/ViewModels/TapesStore.swift:1084` (45)
  9. `insertAtCenter` (binding variant) – `Tapes/ViewModels/TapesStore.swift:842` (45)
  10. `handleAlbumRenameIfNeeded` – `Tapes/ViewModels/TapesStore.swift:1176` (42)
- **Build settings of note:** `SWIFT_VERSION` 5.0, `ENABLE_PREVIEWS` enabled, `SWIFT_EMIT_LOC_STRINGS` on for the app target, optimisation levels defaulted (`-Onone`/`-O`), no extra warning or sanitiser flags set.

## Test & CI Review
- Unit coverage focuses almost exclusively on `TapeCompositionBuilder`; exporter edge cases and playback preparation are exercised, but persistence, album lifecycle, importer timeouts, and UI reducers lack tests.
- UITests are boilerplate stubs; no smoke or accessibility assertions exist.
- No continuous integration, static analysis, or formatting automation is present; build.log suggests manual runs only.
- Recommendations: add store/import/export unit tests, snapshot/diff UI tests for SwiftUI views, integrate XCTMemory/Leaks diagnostics, and wire up CI (e.g., GitHub Actions + Xcode Cloud) to run on every PR.

## Risk Register
| Risk | Area | Impact | Probability | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| Imported media missing after restart | Reliability | High | High | Persist media to Application Support, validate on load, add migration | TBD |
| Main-thread persistence stalls UI | Performance | High | High | Introduce persistence actor, throttle saves, add performance tests | TBD |
| Accessibility blockers in primary controls | Accessibility | Medium | High | Replace gesture images with buttons, add VoiceOver UI tests | TBD |

## 90-Day Remediation Plan
- **Phase 1 (Weeks 1–2): Critical fixes & performance blockers**
  - Persist imported media outside `tmp`, add migration for existing clips.
  - Correct exporter transition mapping and add regression tests.
  - Move persistence to a background actor and add loading guards.
  - Patch accessibility for primary controls and present limited Photos handling.
- **Phase 2 (Weeks 3–6): Architecture, concurrency, accessibility AA, HIG polish**
  - Modularise `TapesStore` into persistence, album, and UI coordinators; inject dependencies for testability.
  - Replace deprecated `NavigationView`/`ActionSheet`, adopt adaptive layouts for iPad/split view.
  - Optimise thumbnail caching and remove redundant `Task.detached` usage.
  - Expand VoiceOver labelling, Dynamic Type support, and localisation scaffolding.
- **Phase 3 (Weeks 7–12): Test coverage, CI hardening, localisation readiness**
  - Implement unit/UI test suites for importer, store, exporter, and accessibility flows.
  - Integrate SwiftLint/SwiftFormat, enable warnings-as-errors, and set up CI pipelines.
  - Prepare for localisation (string tables, RTL checks) and add analytics/diagnostics instrumentation as needed.

## Analysis Method
Reviewed repository structure, Xcode project settings, and all Swift sources (models, view models, UI, platform bridges, exporter). Analysed asynchronous flows, persistence, media handling, and UI composition. Inspected tests, tooling footprint, and build configuration. Verified guideline alignment against Apple HIG, App Store Review, WCAG, and energy best practices. Findings are evidence-backed with path references and focus on actionable remediation.
