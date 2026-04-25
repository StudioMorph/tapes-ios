# Ad Integration — Implementation Plan

**Status:** Approved for implementation  
**Date:** 25 April 2026

---

## 1. Summary

Integrate 15-second non-skippable video ads into Tapes for free-tier users. Ads play inline within the tape playback timeline — pre-roll before the first clip, mid-roll every ~5 minutes of cumulative playback. Plus subscribers never see ads. Uses Google IMA SDK (VAST, app-side scheduling) via SPM.

---

## 2. User Experience

### What the user sees

- Tape opens → ad plays full-screen before the first clip (pre-roll).
- For tapes longer than 5 minutes, an ad plays after the first clip that finishes past the 5-minute cumulative mark since the last ad (mid-roll).
- Ads never interrupt a clip mid-playback.
- Google's default ad UI displays (countdown, "Ad" badge, "Learn More" link — all SDK-provided).
- Player controls (play/pause, prev/next, scrubber) remain **visible but disabled** during the ad.
- The **close/exit button stays active** — user can always leave the player.
- Background music pauses during the ad, resumes after.
- When the ad finishes, playback continues seamlessly to the next real clip.
- Tapping Replay plays the pre-roll again.

### Failure states

- **Ad fails to load (online):** silently skip, play the next clip immediately.
- **User is offline:** show a branded full-screen message over a blurred background:
  - SF Symbol icon (e.g. `wifi.slash`)
  - "You're offline, so we can't load ads."
  - "Tapes is free because of ads — but we've got you."
  - "Your tape will play in 0:10" (countdown from 10 seconds)
  - Styled with `Tokens.Colors` and app typography
  - After countdown, dismiss and play the tape without ads.

### Who sees ads

- **Free tier:** ads on all tapes (own, shared, collab).
- **Plus tier (£3.99):** no ads, ever.
- Check `EntitlementManager.isPremium` at the start of every `TapePlayerViewModel.prepare()`. This is a local read, not a network call.
- No exports contain ads — only the existing logo watermark.

---

## 3. Technology

### SDKs (both via Swift Package Manager)

| SDK | Repository | Purpose |
|-----|-----------|---------|
| Google IMA SDK | `swift-package-manager-google-interactive-media-ads-ios` | Video ad playback |
| Google UMP SDK | `swift-package-manager-google-user-messaging-platform` | GDPR/ATT consent management |

### Ad scheduling approach

**VAST with app-side scheduling** (not VMAP). Rationale: the Tapes player is clip-sequential (individually-loaded `AVPlayerItem`s), not a single continuous stream. VMAP's `IMAContentPlayhead`-based scheduling assumes a single stream and would require a fragile synthetic playhead. App-side scheduling is more robust.

### Ad tag

Single constant in `AdConfig.swift`. During development, use Google's public sample pre-roll tag. Later, swap for the real Ad Manager unit ID (`/XXXXXXXX/tapes_video_preroll`).

**Development tag:**
```
https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator=
```

---

## 4. Architecture

### New files

| File | Purpose |
|------|---------|
| `Tapes/Core/Ads/AdConfig.swift` | Ad tag URL constant. One-line swap for production. |
| `Tapes/Core/Ads/AdManager.swift` | Owns `IMAAdsLoader` (singleton, reused per Google guidance). Handles ad requests, `IMAAdsLoaderDelegate`, `IMAAdsManagerDelegate`. Exposes async API: `requestAd() → Bool` (success/failure). |
| `Tapes/Core/Ads/AdPlayerContainerController.swift` | `UIViewController` subclass hosting `IMAAdDisplayContainer`. IMA SDK requires a `UIViewController` context. Minimal — just provides the container and forwards lifecycle. |
| `Tapes/Views/Player/AdContainerRepresentable.swift` | `UIViewControllerRepresentable` wrapping `AdPlayerContainerController` for SwiftUI embedding. |
| `Tapes/Views/Player/OfflineAdView.swift` | Full-screen branded countdown view for offline users. Uses design tokens, SF Symbols, 10-second countdown. |
| `Tapes/Core/Privacy/ConsentManager.swift` | Wraps Google UMP SDK. Checks consent status, presents form if required, exposes `canRequestAds`. Also triggers ATT prompt after UMP flow. |

### Existing files modified

| File | Changes |
|------|---------|
| `Tapes/Views/Player/TapePlayerView.swift` | Add ad container layer in `ZStack`. Show/hide based on ad state. Disable controls (not hide) during ad. Show `OfflineAdView` when offline + free. |
| `Tapes/Views/Player/TapePlayerViewModel.swift` | Add ad-aware playback logic: check `isPremium`, check network, request pre-roll before clip 0, track cumulative time for mid-roll, pause/resume background music around ads, handle ad completion/failure callbacks. |
| `Tapes/Components/PlayerControls.swift` | Accept `isDisabled: Bool` parameter. When true, all buttons disabled (greyed out). |
| `Tapes/Components/PlayerProgressBar.swift` | Accept `isDisabled: Bool` parameter. When true, scrubber non-interactive (drag gesture removed). |
| `Tapes/TapesApp.swift` | Pre-warm `IMAAdsLoader` at launch. Trigger UMP consent check + ATT prompt. |
| `Info.plist` | Add `NSUserTrackingUsageDescription` key. Add `GADApplicationIdentifier` (required by UMP SDK). |

### Not modified

- `EntitlementManager.swift` — `isPremium` already covers Plus tier. No changes needed.
- `TapeCompositionBuilder.swift` — ad playback is separate from clip composition.
- `Clip.swift`, `Tape.swift` — ads are not modelled as clips.

---

## 5. Detailed flow

### 5.1 App launch

```
TapesApp.task {
    ConsentManager.shared.requestConsentIfNeeded(from: rootViewController)
    // UMP SDK shows GDPR form if in EEA + not yet consented
    // Then triggers ATT prompt if not yet determined
    // After both: AdManager.shared.canServeAds is set
    AdManager.shared.preWarm()  // initialises IMAAdsLoader
}
```

### 5.2 Tape playback begins

```
TapePlayerViewModel.prepare() {
    let isFree = !entitlementManager.isPremium
    if isFree {
        if isOnline {
            // Request pre-roll ad
            let adLoaded = await adManager.requestAd(in: adContainer)
            if adLoaded {
                // IMA SDK plays the ad
                // Delegate fires didRequestContentPause → we pause content
                // Ad plays with SDK default UI
                // Controls stay visible but disabled
                // Background music paused
                // Delegate fires didRequestContentResume → we resume
                // Load clip 0 and play
            } else {
                // No fill / error → play clip 0 immediately
            }
        } else {
            // Show OfflineAdView (10s countdown)
            // After countdown → play clip 0
        }
    } else {
        // Plus user → play clip 0 immediately, no ads
    }
}
```

### 5.3 Mid-roll logic

```
handleClipFinished() {
    cumulativePlaybackTime += clipDuration
    if isFreeUser && cumulativePlaybackTime >= 300 {  // 5 minutes
        cumulativePlaybackTime = 0  // reset
        if isOnline {
            // Request mid-roll ad (same flow as pre-roll)
        } else {
            // Show OfflineAdView
        }
        // Then continue to next clip
    } else {
        // Normal: jump to next clip
    }
}
```

### 5.4 IMA SDK delegate lifecycle

1. `adsLoader(_:adsLoadedWith:)` — receive `IMAAdsManager`, set delegate, call `initialize()`, then `start()`.
2. `adsManager(_:didReceive:)` — listen for `.LOADED`, `.STARTED`, `.COMPLETE`, `.ALL_ADS_COMPLETED` events.
3. `adsManagerDidRequestContentPause(_:)` — pause content AVPlayer, pause background music, show ad container, disable controls.
4. `adsManagerDidRequestContentResume(_:)` — hide ad container, enable controls, resume background music, continue to next clip.
5. `adsLoader(_:failedWith:)` — log error, skip ad slot, play content.

### 5.5 Replay

When user taps Replay:
- Reset `cumulativePlaybackTime` to 0
- Treat as fresh playback — pre-roll plays again

---

## 6. Privacy and consent

### ATT (App Tracking Transparency)

- Add `NSUserTrackingUsageDescription` to `Info.plist`:
  > "Tapes uses this to show you relevant ads. You can change this anytime in Settings."
- `ConsentManager` calls `ATTrackingManager.requestTrackingAuthorization()` after UMP consent flow.
- If user denies: IMA SDK serves non-personalised ads (lower CPM, still functional).

### GDPR (Google UMP SDK)

- `ConsentManager` calls `UMPConsentInformation.sharedInstance.requestConsentInfoUpdate()` at launch.
- If in EEA and consent not yet given: `UMPConsentForm.loadAndPresentIfRequired()` shows Google's consent dialog.
- Check `UMPConsentInformation.sharedInstance.canRequestAds` before any ad request.
- Provide a "Privacy Settings" entry in `PreferencesView` when `privacyOptionsRequirementStatus == .required` so users can change their choice later.

### Order of operations at launch

1. UMP consent info update (determines if user is in EEA)
2. UMP consent form (if required)
3. ATT prompt (if not yet determined)
4. Set `canServeAds` based on both results
5. Pre-warm `IMAAdsLoader`

---

## 7. Network detection

Use `NWPathMonitor` (already imported in `PreferencesView` for preference sync). Create a lightweight `NetworkMonitor` singleton or inject from app root. Check `path.status == .satisfied` before ad requests.

If offline when an ad slot triggers:
- Show `OfflineAdView` with 10-second countdown
- After countdown, dismiss and play content
- No retry — if they come back online mid-tape, the next ad slot will attempt normally

---

## 8. Implementation order

| Step | What | Risk |
|------|------|------|
| 1 | Add IMA SDK + UMP SDK via SPM | Low — dependency addition only |
| 2 | Create `AdConfig`, `ConsentManager`, `AdManager` | Low — new files, no existing code touched |
| 3 | Create `AdPlayerContainerController` + `AdContainerRepresentable` | Low — UIKit wrapper |
| 4 | Create `OfflineAdView` | Low — pure SwiftUI view |
| 5 | Create `NetworkMonitor` | Low — utility class |
| 6 | Modify `PlayerControls` + `PlayerProgressBar` — add `isDisabled` | Low — additive parameter |
| 7 | Modify `TapePlayerView` — embed ad container, wire controls disable | Medium — core player view |
| 8 | Modify `TapePlayerViewModel` — ad-aware playback logic | Medium — core playback state |
| 9 | Wire `ConsentManager` + ATT in `TapesApp` | Low |
| 10 | Add `Info.plist` keys | Low |
| 11 | Test with Google sample tags | — |
| 12 | Documentation | — |

---

## 9. Testing plan

1. **Free user, online:** verify pre-roll plays before first clip, controls disabled during ad, close button works, ad completes → clip 1 plays seamlessly.
2. **Free user, 5+ min tape:** verify mid-roll plays after the first clip finishing past 5-minute mark.
3. **Free user, offline:** verify offline countdown view appears for 10 seconds, then tape plays.
4. **Plus user:** verify no ads load, no ad container visible, player behaves exactly as before.
5. **Ad failure (no fill):** use an intentionally broken tag URL → verify silent skip, tape plays.
6. **Replay:** verify pre-roll plays again on replay.
7. **Background music:** verify it pauses during ad and resumes after.
8. **ATT prompt:** verify it appears once, stores choice, does not reappear.
9. **GDPR (EEA test):** use UMP debug geography → verify consent form appears.
10. **Close during ad:** verify tapping close dismisses the entire player cleanly.

---

## 10. Open items (deferred)

- Custom ad UI overlay (yellow scrubber, branded badge, custom countdown) — deferred, using SDK default UI for now.
- Post-roll ads — not planned.
- Together tier / Founders tier — only Free and Plus for now.
- Staging environment for ad testing — use Google sample tags until Ad Manager account approved.
- Ad analytics / reporting dashboard — post-launch.
