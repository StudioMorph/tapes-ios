# Mubert Silent Fallback Removal

**Status:** draft, awaiting approval.
**Scope:** iOS only. Three files touched.
**Risk:** low — removes a fallback that's actively harmful. The replacement is strictly better UX.
**Deploy posture:** ships with next iOS build.
**Relationship to other plans:** this is independent of the Mubert server-side proxy plan (`tapes-api/docs/plan/MubertServerProxy.md`). The proxy plan moves credentials off-device; this plan fixes what happens when Mubert fails. We should do this one first — it's smaller, it fixes a real user-facing bug, and the proxy plan inherits the improved failure semantics.

---

## Problem

[Tapes/Core/Music/MubertAPIClient.swift:304-314](../../Tapes/Core/Music/MubertAPIClient.swift:304) — on HTTP 401 from Mubert:

```swift
if httpResponse.statusCode == 401 {
    let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
    log.warning("API returned 401 — falling back to mock. Body: \(responseBody)")
    let url = try await downloadMockTrack(mood: mood, tapeID: tapeID)
    onProgress(1.0)
    return url
}
```

`downloadMockTrack` calls `generateToneWav` which synthesises a 30-second 220 Hz sine wave WAV, writes it to `Caches/mubert_tracks/<tapeID>.mp3` (note: WAV bytes, `.mp3` extension), returns the URL.

`AVAudioPlayer(contentsOf:)` is forgiving about container-vs-extension mismatches and will happily decode the WAV. The user gets a looping 220Hz drone behind their tape.

**When this bites:**
- Mubert token expired or revoked.
- Mubert rate-limiting our account.
- Hardcoded credentials rotated by Mubert (plausible as their platform matures).
- Any server-side Mubert outage that returns 401.

Once a bad "track" is cached per tape, the sine wave persists across sessions until the cache is cleared. The user has no visibility into why their tape sounds wrong, and no way to retry.

**Compounding issue:** the cached file is keyed by tape ID. If the fallback fires once for a tape, *every subsequent export of that tape* uses the sine wave, because [`cachedTrackURL(for:)`](../../Tapes/Core/Music/MubertAPIClient.swift:274) sees the file and returns it without re-generating.

---

## Fix

Three changes:

### Change 1 — Remove the 401 fallback

**File:** [Tapes/Core/Music/MubertAPIClient.swift](../../Tapes/Core/Music/MubertAPIClient.swift)

Replace the 401 branch with a hard throw. Delete `downloadMockTrack` and `generateToneWav` entirely — they're ~50 lines of dead code after the 401 branch goes.

```swift
// Before
if httpResponse.statusCode == 401 {
    let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
    log.warning("API returned 401 — falling back to mock. Body: \(responseBody)")
    let url = try await downloadMockTrack(mood: mood, tapeID: tapeID)
    onProgress(1.0)
    return url
}

// After
if httpResponse.statusCode == 401 {
    let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
    log.error("Mubert 401 — credentials rejected. Body: \(responseBody, privacy: .public)")
    throw APIError.notConfigured
}
```

`APIError.notConfigured` already exists in the enum and has a localized description: "Music service is not yet configured." Reuse it. (If we want a different string — "Music service is temporarily unavailable" — add a new case.)

Delete `downloadMockTrack(mood:tapeID:)` and `generateToneWav(durationSeconds:frequency:)`. Keep imports; `Foundation` is still needed elsewhere.

### Change 2 — Surface the failure to the user via `BackgroundMusicPlayer`

**File:** [Tapes/Core/Music/BackgroundMusicPlayer.swift](../../Tapes/Core/Music/BackgroundMusicPlayer.swift)

Today `prepare(mood:tapeID:volume:)` catches any error and stores `self.error = error.localizedDescription`. That property exists but I haven't found a view that displays it. Either wire it into the player UI so the user sees a small inline banner, or at minimum ensure the tape plays silently (no music, no sine wave) when the fetch fails.

Current behaviour on failure after this change:
- `MubertAPIClient.generateTrack` throws.
- `BackgroundMusicPlayer.prepare` catches, sets `error`, `isLoading = false`.
- `audioPlayer` remains `nil`.
- `syncPlay()` sees `audioPlayer == nil` and sets `pendingPlay = true` — the flag is then never fulfilled because `audioPlayer` won't appear. Effect: silent playback. No loop.
- Tape plays with no background music. Correct silent failure.

The minimum viable fix is: verify the above is indeed what happens, because that's the desired state.

The *better* fix is to add a small user-visible affordance. Options:

- **Option A (minimum):** do nothing further; silent failure is acceptable, the user will notice the absence of music.
- **Option B (recommended):** the Background Music picker in Tape Settings should show a "Couldn't load music, try again" state when `BackgroundMusicPlayer.error != nil`. A tap retries `prepare`.
- **Option C:** inline banner in the player UI — too invasive for the scope of this plan.

I'd go with **Option A** for this plan, and flag Option B as a separate UX plan. The bug being fixed is the silent-with-drone case; eliminating it is enough for this scope. If the user wants the nice affordance now, I'll expand.

### Change 3 — Clean up existing sine-wave caches

**File:** [Tapes/TapesApp.swift](../../Tapes/TapesApp.swift) — a one-shot cleanup on app launch, for users who already have sine-wave `.mp3` files cached from prior builds.

```swift
init() {
    AppearanceConfigurator.setupNavigationBar()
    cleanupTempImports()
    cleanupLegacyMockMusicTracks()        // ← new
    if #available(iOS 26, *) {
        ExportCoordinator.registerBackgroundExportHandler()
        ShareUploadCoordinator.registerBackgroundUploadHandler()
    }
}

private func cleanupLegacyMockMusicTracks() {
    // Remove all files in Caches/mubert_tracks/ on first launch of the build
    // that removes the mock fallback. Cached tracks are cheap to re-generate.
    let defaults = UserDefaults.standard
    let flagKey = "tapes_cleaned_mock_music_v1"
    guard !defaults.bool(forKey: flagKey) else { return }

    let cacheDir = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("mubert_tracks", isDirectory: true)

    try? FileManager.default.removeItem(at: cacheDir)
    defaults.set(true, forKey: flagKey)
}
```

Why: any user who has shared a tape with background music in a build where the 401 fallback fired will have a sine-wave file in their cache. Re-opening that tape without the cleanup would play the drone again — the new code throws, but `cachedTrackURL(for:)` short-circuits before any API call happens if the file exists.

The flag `tapes_cleaned_mock_music_v1` ensures the cleanup runs once per device, not every launch. Cached tracks are a convenience, not load-bearing — re-generating is fine.

---

## Risks

- **Users mid-generation when we ship this.** If a user happens to be generating a track as the new build installs, they'll see it fail instead of fall back. Tiny window. Acceptable.
- **Wiped cache means next tape play re-fetches.** On devices with many tapes, first re-play after upgrade re-runs the Mubert request for each tape the user opens. If Mubert is healthy, this is 10-60s per tape. If Mubert is in a bad state, every tape shows silent music (which is the correct behaviour). Acceptable.
- **If the cleanup flag key collides with an existing UserDefaults key** — it shouldn't, the prefix `tapes_` is scoped. Double-check before merging.

---

## Verification

1. Before deploy: on your device, if there's currently a cached music track for any tape, confirm tapes play with music (real Mubert track, not sine wave). Otherwise nothing to compare to.
2. Ship the change. Launch the app. Confirm `Caches/mubert_tracks/` is empty (you can navigate there via the Files app if the app exposes its sandbox, or via Xcode's "Devices" → container download).
3. Open a tape with a mood set. Confirm playback generates a new track (shows the progress UI), plays real Mubert audio, not a drone.
4. Negative test: deliberately break Mubert credentials — easiest way is to edit the customer ID in the source to garbage, build & run, expect 401 from Mubert. Open a tape with a mood. Confirm: tape plays silently (no music), no sine-wave drone. Check Console for the `Mubert 401 — credentials rejected` log. Restore credentials.
5. `Caches/mubert_tracks/` should have the real MP3 only, no `.mp3` files that are actually WAV under the hood. `file /path/to/tape.mp3` should show "Audio file with ID3 version …" for real Mubert tracks. (Optional paranoia step.)

---

## Deploy

iOS-only, next build.

---

## Open questions

- Do we want a user-visible "retry music" affordance (Option B above) in this plan, or as a follow-up? My vote: follow-up.
- Should we cap retries per tape per session to avoid a failing Mubert hammering the API? Yes, but the existing code does this implicitly via the cache — if the generation fails, nothing cached, next open retries. For now, good enough.
