# Ad Integration

## Summary

Interstitial ads integrated into tape playback for free-tier users using Google AdMob SDK. Ads appear at natural transition points — pre-roll before the first clip, mid-roll every ~5 minutes — as full-screen interstitials. Plus subscribers never see ads.

## Purpose & Scope

Monetise free-tier usage with non-intrusive interstitial ads. The feature gates on `EntitlementManager.isPremium` checked at the start of every playback session. When offline, a branded countdown fallback (10 seconds) takes the place of an ad.

## SDKs

| SDK | Version | Purpose |
|-----|---------|---------|
| Google Mobile Ads SDK (GoogleMobileAds) | 11.13.0 | AdMob interstitial ad serving |
| Google UMP SDK (GoogleUserMessagingPlatform) | 2.7.0 | GDPR/ATT consent management |

Both installed via Swift Package Manager.

## Key UI Components

- **Interstitial ads**: Full-screen ads presented by AdMob SDK via `GADInterstitialAd.present(fromRootViewController:)`. No custom ad container needed — the SDK manages its own presentation.
- **Offline ad view** (`OfflineAdView`): Branded countdown (10 seconds) shown when offline. Uses `Tokens.Colors`, SF Symbols (`wifi.slash`), app typography.
- **Player controls** (`PlayerControls`, `PlayerScrubBar`): Accept `isDisabled` parameter. When an ad is playing, controls are hidden. Scrub bar turns yellow.
- **Close button**: Remains active during ads — user can always leave.

## Data Flow

```
TapesApp launch
  → ConsentManager.requestConsentIfNeeded()  (UMP → ATT)
  → AdManager.start()                        (initialise SDK + preload first interstitial)

Tape playback begins
  → TapePlayerViewModel.prepare(entitlementManager:)
     → isFreeUser = !entitlementManager.isPremium
     → playAdSlotIfNeeded()
        → Online: AdManager.showAd() → full-screen interstitial
        → Offline: OfflineAdView (10s countdown)
     → Play clip 0

Clip finishes
  → cumulativePlaybackTime += clipDuration
  → If free user && cumulative >= 300s:
     → Reset timer, show mid-roll interstitial
     → Continue to next clip

Ad dismissed
  → AdManager preloads next interstitial immediately
     (GADInterstitialAd is one-time-use; next ad must be loaded fresh)
```

## Files

| File | Role |
|------|------|
| `Core/Ads/AdConfig.swift` | Ad unit ID, timing configuration |
| `Core/Ads/AdManager.swift` | AdMob interstitial lifecycle — load, present, delegate callbacks |
| `Core/Ads/NetworkMonitor.swift` | `NWPathMonitor` wrapper for connectivity checks |
| `Core/Privacy/ConsentManager.swift` | UMP SDK + ATT consent flow |
| `Views/Player/OfflineAdView.swift` | Offline countdown fallback |

## Modified Files

| File | Change |
|------|--------|
| `TapesApp.swift` | SDK init via `AdManager.start()`, consent flow |
| `TapePlayerView.swift` | Ad state drives control visibility, close button during ads |
| `TapePlayerViewModel.swift` | Ad-aware playback: pre-roll, mid-roll, offline, entitlement check |
| `PlayerControls.swift` | `isDisabled` parameter |
| `PlayerProgressBar.swift` | `isDisabled` parameter |
| `Info.plist` | `NSUserTrackingUsageDescription`, `GADApplicationIdentifier`, `SKAdNetworkItems` |
| `project.pbxproj` | Google Mobile Ads + UMP SPM package references |

## Configuration

- **Ad unit ID**: `AdConfig.interstitialAdUnitID` — production AdMob interstitial unit.
- **Mid-roll interval**: `AdConfig.midRollInterval` (300 seconds / 5 minutes).
- **Offline countdown**: `AdConfig.offlineCountdownDuration` (10 seconds).
- **GAD App ID** (`Info.plist`): Production ID `ca-app-pub-1250336305586665~3052774017`.
- **SKAdNetworkItems** (`Info.plist`): Full list of Google-recommended SKAdNetwork identifiers for ad attribution.

## Testing Considerations

1. **Free user, online**: Pre-roll interstitial before first clip, controls hidden during ad, close button works.
2. **Free user, 5+ min tape**: Mid-roll interstitial after cumulative 5 minutes.
3. **Free user, offline**: Offline countdown view appears, tape plays after 10 seconds.
4. **Plus user**: No ads, player behaves exactly as before.
5. **Ad load failure**: Silent skip — tape plays immediately.
6. **Replay**: Pre-roll plays again, cumulative timer resets.
7. **Background music**: Pauses during ad, resumes after.
8. **ATT prompt**: Appears once, choice persisted.
9. **GDPR (debug)**: UMP form appears with `UMPDebugSettings.geography = .EEA`.
10. **Close during ad**: Player dismisses cleanly, ad torn down.
11. **Ad expiry**: Ads expire after 1 hour; `AdManager` reloads after each presentation.

## Removed

- **Google IMA SDK** (`GoogleInteractiveMediaAds`) — replaced by Google Mobile Ads SDK.
- **`AdContainerRepresentable.swift`** — UIKit ad container no longer needed; AdMob interstitials manage their own presentation.
- **VAST ad tag URL** — replaced by AdMob ad unit ID.
