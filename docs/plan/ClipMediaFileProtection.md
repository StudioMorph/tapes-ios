# Clip Media File Protection

**Status:** draft, awaiting approval.
**Scope:** iOS only. Modifies how files are written in two places; adds a one-time migration for existing files.
**Risk:** low-medium — applies a file-protection class to persisted media. If set wrong, app could fail to read its own files when the device is locked.
**Deploy posture:** ships with next iOS build. One-time migration runs on first launch.

---

## Problem

Two kinds of user data are written to the app sandbox without explicit `FileProtectionType`:

1. **Tape metadata:** `Documents/tapes.json` — contains all tape titles, clip IDs, share info (including `remoteTapeId` and `shareId`), tape settings.
2. **Clip media blobs:** `Documents/clip_media/<id>_thumb.jpg`, `Documents/clip_media/<id>_image.dat` — JPEG thumbnails and full-resolution image bytes for imported photos (rare, mostly used only for photos imported without an asset identifier).

iOS default is `FileProtectionType.completeUntilFirstUserAuthentication`. This means files are unreadable until the user unlocks the device the first time after boot, then remain readable until reboot. That's already a reasonable baseline — but the code doesn't set it explicitly. We rely on the OS default, which has varied across iOS versions.

**What we want:**
- For `tapes.json`: `FileProtectionType.completeUntilFirstUserAuthentication` — we need to be able to read it early in app launch, including when the device is locked but has been unlocked once since boot (background push processing, for example).
- For `clip_media/*`: same. These are accessed during playback and export, which can happen while the device is in a locked state in some flows, but generally not on a cold-locked device.

Neither should be `FileProtectionType.complete`, which would make them unreadable when the screen is locked. That breaks background push processing and any scenario where the app needs to access data while the phone is sleeping.

**Additional concern flagged in the review:** raw photo bytes (`_image.dat`) are full-size user photos duplicated from the Photos library into the app container. Beyond file protection, this is a data-minimisation concern. That's a separate design question — are we going to continue storing these? — and not in scope for this plan. This plan just makes sure what we *do* store is protected.

---

## Fix

Three changes:

### Change 1 — Explicit `FileProtectionType` on new writes

**File:** [Tapes/ViewModels/TapesStore.swift](../../Tapes/ViewModels/TapesStore.swift)

Inside `TapePersistenceActor`, two writes happen:

- `save(_:to:)` line ~40: `try data.write(to: url)` (for `tapes.json`).
- `saveBlobFiles(for:)` line ~93 (in `saveBlobFiles`): `try? thumb.write(to: url)` and `try? img.write(to: url)`.

Change each to use the `.completeUntilFirstUserAuthentication` option:

```swift
// tapes.json
try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

// clip_media blobs
try thumb.write(to: url, options: [.completeFileProtectionUntilFirstUserAuthentication])
try img.write(to: url, options: [.completeFileProtectionUntilFirstUserAuthentication])
```

The constant `.completeFileProtectionUntilFirstUserAuthentication` is part of `Data.WritingOptions` from Foundation.

### Change 2 — Set directory-level protection

Directory-level protection is applied via `FileManager.setAttributes`:

```swift
// In TapePersistenceActor.init
try? FileManager.default.setAttributes(
    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
    ofItemAtPath: mediaDir.path
)
```

This ensures files created in the directory inherit the protection class, as a belt-and-braces. The `.atomic` write uses a temp file + rename, so directory protection matters.

Apply the same for the Documents directory where `tapes.json` lives, if it isn't already protected (it should be by default, but setting explicitly is safe).

### Change 3 — One-time migration for existing files

For users upgrading, existing files were written without the explicit flag. Re-apply protection on app launch, one-time, flag-gated:

```swift
// In TapesApp.init or as a dedicated helper called from init
private func applyMediaFileProtection() {
    let defaults = UserDefaults.standard
    let flagKey = "tapes_applied_file_protection_v1"
    guard !defaults.bool(forKey: flagKey) else { return }

    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    let mediaDir = docs.appendingPathComponent("clip_media", isDirectory: true)
    let tapesJson = docs.appendingPathComponent("tapes.json")

    let attrs: [FileAttributeKey: Any] = [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
    ]

    try? fm.setAttributes(attrs, ofItemAtPath: docs.path)
    try? fm.setAttributes(attrs, ofItemAtPath: mediaDir.path)
    try? fm.setAttributes(attrs, ofItemAtPath: tapesJson.path)

    if let contents = try? fm.contentsOfDirectory(atPath: mediaDir.path) {
        for file in contents {
            let path = mediaDir.appendingPathComponent(file).path
            try? fm.setAttributes(attrs, ofItemAtPath: path)
        }
    }

    defaults.set(true, forKey: flagKey)
}
```

Call from `TapesApp.init()` after `cleanupTempImports()`.

---

## Why `completeUntilFirstUserAuthentication` and not `complete`

The stronger `FileProtectionType.complete` makes files unreadable whenever the device is locked. That breaks:

- Background push handling (our `PushNotificationManager.handleBackgroundPush` reads the tape list to resolve a pushed `tape_id`).
- Any scheduled background task that needs to touch persisted state (current `BGContinuedProcessingTask` for upload/export doesn't read tapes.json during background execution, but this could change).

`completeUntilFirstUserAuthentication` means: after the first unlock following a reboot, the files are accessible. Lock the phone, files stay accessible. Reboot, files are inaccessible until first unlock. That's the right tradeoff for this app — the data is at-rest encrypted when the device is powered off, and the common "phone was stolen" scenario typically involves the device being rebooted, which means the thief can't read our files without the passcode.

---

## Risks

- **Protection class wrong** — if we accidentally set `.complete` instead of `.completeUntilFirstUserAuthentication`, background push handling fails. Mitigation: explicit constant names in the code, not a bare integer.
- **Migration re-runs on already-migrated files** — idempotent. `setAttributes` just overwrites the attribute. No harm.
- **Users with corrupt files** — the migration does `try?`, so failures are silent. If a file can't be read at all, `setAttributes` fails silently, and the next read path already handles missing files. No new failure mode.
- **Future files written outside the actor** — if new code adds file writes in `Documents/` without going through `TapePersistenceActor`, they won't get the protection flag. Mitigation: this plan makes the patterns explicit; future code reviews enforce.

---

## Verification

1. On your device, before the change: check existing file protection class.

   Easiest way: build a small throwaway debug helper that reads `FileAttributeKey.protectionKey` from `tapes.json` and logs the value. Or use Xcode's Devices window → download container → inspect via `xattr`. (The latter only tells you the file content, not the protection class; the former is more reliable.)

2. Ship the change. Launch the app once so the migration runs.

3. On the same device, re-check the protection class. Expected: `FileProtectionType.completeUntilFirstUserAuthentication`.

4. Functional test: lock your device. Wait 30 seconds. Unlock. Open Tapes. Confirm:
   - Tapes list loads normally.
   - Tap a tape, confirm clips load.
   - Background: send yourself a share notification from Isabel's device while your phone is locked. Unlock and check the badge updated correctly (this exercises the `handleBackgroundPush` path).

5. Reboot test: power off your device completely, power on, *do not unlock yet*. Check that no Tapes notifications arrive or are processed in the locked-before-first-unlock window. Then unlock, open Tapes, confirm everything works.

---

## Deploy

iOS-only, next build.

---

## Open questions

- **Should we also delete `_image.dat` files entirely and move to a pure-PHAsset model?** Big question. Data minimisation for App Review, also removes the whole class of "raw photo bytes in container" concern. But it's a separate, larger plan — for now we protect what exists, and the data-minimisation work is its own thing.
- **Should `tmp/Imports` also be protected?** Files in `tmp` get purged by the OS under storage pressure; they're not a persistent concern. `tmp` already gets a default protection class that's less than `complete`. Leaving as-is.
