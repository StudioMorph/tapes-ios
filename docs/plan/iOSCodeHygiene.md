# iOS Code Hygiene

**Status:** draft, awaiting approval.
**Scope:** iOS only (`tapes-ios`). No backend, no Xcode project structure changes.
**Risk:** very low — surgical edits in three unrelated files.
**Deploy posture:** no deploy — ships with the next build like any iOS change.

---

## Problem

Three small issues surfaced in the review, all trivial on their own, grouped here because they're the same shape: "the code isn't doing what it clearly intended to do."

1. `AppearanceConfigurator.setupNavigationBar()` exists but nothing ever calls it. The centralised nav-bar styling that was set up during the nav-background audit isn't actually installed at runtime.
2. Two `print()` statements in `TapesStore.selectTape` emit user-generated content (tape titles) to the device log in Release builds.
3. Two files log under a different subsystem (`com.tapes.app`) than everything else (`com.studiomorph.tapes`), splitting Console.app filtering.

---

## Fix 1 — Wire up `AppearanceConfigurator`

**File:** [Tapes/TapesApp.swift](../../Tapes/TapesApp.swift:16)

**Change:** call the setup in `TapesApp.init()`.

```swift
init() {
    AppearanceConfigurator.setupNavigationBar()
    cleanupTempImports()
    if #available(iOS 26, *) {
        ExportCoordinator.registerBackgroundExportHandler()
        ShareUploadCoordinator.registerBackgroundUploadHandler()
    }
}
```

One line. The configurator already does the right thing — it just needs to be invoked.

---

## Fix 2 — Gate debug prints in `TapesStore`

**File:** [Tapes/ViewModels/TapesStore.swift](../../Tapes/ViewModels/TapesStore.swift:308)

**Change:** replace the two `print()` calls in `selectTape(_:)` with `TapesLog.store.debug(…)` using `privacy: .private(mask: .hash)` on the tape title. The `TapesLog.store` logger routes through `os.log` and is already used elsewhere in the file.

```swift
public func selectTape(_ tape: Tape) {
    TapesLog.store.debug("TapesStore.selectTape called for: \(tape.title, privacy: .private(mask: .hash))")
    selectedTape = tape
    showingSettingsSheet = true
    TapesLog.store.debug("showingSettingsSheet set to: \(self.showingSettingsSheet, privacy: .public)")
}
```

Why `privacy: .private(mask: .hash)`: tape titles are user content. Unified logging respects the privacy qualifier — on Release builds, the title will be replaced with a stable hash. During development, attaching the Xcode debugger or running via simulator keeps the full value visible.

Why keep the second log at all: the state transition is useful when debugging the settings-sheet-not-opening issues that triggered these prints originally. Changing the emoji to drop the `🔧` prefix while we're there — it reads as ad-hoc debug left in by accident.

---

## Fix 3 — Unify logger subsystems

**Files:**
- [Tapes/Core/Music/MubertAPIClient.swift:11](../../Tapes/Core/Music/MubertAPIClient.swift:11)
- [Tapes/Core/Music/BackgroundMusicPlayer.swift:12](../../Tapes/Core/Music/BackgroundMusicPlayer.swift:12)

**Change:** both files declare private `Logger(subsystem: "com.tapes.app", …)`. The rest of the codebase uses `com.studiomorph.tapes` via the shared `TapesLog` struct. Switch these two to use `TapesLog` — add new categories if one doesn't exist, or reuse the closest match.

```swift
// In TapesLog.swift — add if not already present
static let music = Logger(subsystem: "com.studiomorph.tapes", category: "Music")
```

```swift
// MubertAPIClient.swift — replace the private log
private let log = TapesLog.music
```

```swift
// BackgroundMusicPlayer.swift — same
private let log = TapesLog.music
```

Net result: one `Music` category under the same subsystem as everything else. Console.app with subsystem filter `com.studiomorph.tapes` shows everything; no more "where did that Mubert log go".

---

## Risks

- **Fix 1:** if `AppearanceConfigurator` conflicts with the inline `.toolbarBackground(.hidden, …)` modifiers already in views, we could see a visually different nav bar on some screens. The configurator sets an opaque background with the primary background colour; the inline hidden modifiers should override per-screen. Verify visually on both light and dark mode, on the My Tapes list and the Shared tab, after the change.
- **Fix 2:** none. Moving from `print` to `os.log` is strictly better. If Xcode's debug console was something someone was visually scanning during development, they'll need to enable the relevant category in Console.app — but that's also how everything else in the codebase works.
- **Fix 3:** none. `os.log` subsystem labels are filtering metadata, not behaviour.

---

## Verification

1. Build clean, run on device.
2. Launch the app — check nav bar appearance matches design (both light and dark).
3. Open a tape, tap the settings gear — observe settings sheet opens.
4. In Console.app, filter `subsystem:com.studiomorph.tapes category:Store` — see the new `selectTape` debug lines.
5. Trigger a Mubert track generation on a shared tape with background music — confirm logs appear under `category:Music` in Console.app.
6. Switch to a Release build (Product → Scheme → Run → Build Configuration → Release) — confirm the debug lines don't appear (or appear masked) unless the debugger is attached.

---

## Deploy

No deploy step. Ships with the next build in the normal way.

---

## Open questions

None.
