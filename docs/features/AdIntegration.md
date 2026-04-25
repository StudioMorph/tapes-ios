# Ad Integration

## Summary

Video ads integrated into tape playback for free-tier users using Google IMA SDK. Ads play inline within the tape timeline — pre-roll before the first clip, mid-roll every ~5 minutes — with controls disabled during playback. Plus subscribers never see ads.

## Purpose & Scope

Monetise free-tier usage while preserving the Tapes brand experience. Ads appear as native-feeling segments within the tape player, not as overlays or modals. The feature gates on `EntitlementManager.isPremium` checked at the start of every playback session.

## SDKs

| SDK | Version | Purpose |
|-----|---------|---------|
| Google IMA SDK (GoogleInteractiveMediaAds) | 3.31.0 | VAST video ad playback |
| Google UMP SDK (GoogleUserMessagingPlatform) | 2.7.0 | GDPR/ATT consent management |

Both installed via Swift Package Manager.

## Key UI Components

- **Ad container** (`AdContainerRepresentable` → `AdContainerViewController`): UIKit container required by IMA SDK, wrapped for SwiftUI embedding.
- **Offline ad view** (`OfflineAdView`): Branded countdown (10 seconds) shown when offline. Uses `Tokens.Colors`, SF Symbols (`wifi.slash`), app typography.
- **Player controls** (`PlayerControls`, `PlayerScrubBar`): Accept `isDisabled` parameter. When an ad is playing, controls are greyed out (30% opacity) and non-interactive. Scrub bar turns yellow.
- **Close button**: Remains active during ads — user can always leave.

## Data Flow

```
TapesApp launch
  → ConsentManager.requestConsentIfNeeded()  (UMP → ATT)
  → AdManager.preWarm()                      (initialise IMAAdsLoader)

Tape playback begins
  → TapePlayerViewModel.prepare(entitlementManager:)
     → isFreeUser = !entitlementManager.isPremium
     → playAdSlotIfNeeded()
        → Online: AdManager.requestAndPlayAd() → IMA SDK lifecycle
        → Offline: OfflineAdView (10s countdown)
     → Play clip 0

Clip finishes
  → cumulativePlaybackTime += clipDuration
  → If free user && cumulative >= 300s:
     → Reset timer, play mid-roll ad
     → Continue to next clip
```

## New Files

| File | Role |
|------|------|
| `Core/Ads/AdConfig.swift` | Ad tag URL constant, timing configuration |
| `Core/Ads/AdManager.swift` | IMA SDK lifecycle manager (singleton) |
| `Core/Ads/NetworkMonitor.swift` | `NWPathMonitor` wrapper for connectivity checks |
| `Core/Privacy/ConsentManager.swift` | UMP SDK + ATT consent flow |
| `Views/Player/AdContainerRepresentable.swift` | UIKit-to-SwiftUI bridge for IMA |
| `Views/Player/OfflineAdView.swift` | Offline countdown fallback |

## Modified Files

| File | Change |
|------|--------|
| `TapesApp.swift` | Pre-warm ads, trigger consent flow |
| `TapePlayerView.swift` | Embed ad container, wire isDisabled, offline overlay |
| `TapePlayerViewModel.swift` | Ad-aware playback: pre-roll, mid-roll, offline, entitlement check |
| `PlayerControls.swift` | `isDisabled` parameter |
| `PlayerProgressBar.swift` | `isDisabled` parameter (yellow fill, gesture disabled) |
| `Info.plist` | `NSUserTrackingUsageDescription`, `GADApplicationIdentifier` |
| `project.pbxproj` | IMA + UMP SPM package references |

## Configuration

- **Ad tag URL**: `AdConfig.adTagURL` — single constant to swap from test tag to production.
- **Mid-roll interval**: `AdConfig.midRollInterval` (300 seconds / 5 minutes).
- **Offline countdown**: `AdConfig.offlineCountdownDuration` (10 seconds).
- **GAD App ID** (`Info.plist`): Currently set to Google's test app ID (`ca-app-pub-3940256099942544~1458002511`). Replace with production ID when Ad Manager is approved.

## Testing Considerations

1. **Free user, online**: Pre-roll plays before first clip, controls disabled during ad, close button works.
2. **Free user, 5+ min tape**: Mid-roll plays after cumulative 5 minutes.
3. **Free user, offline**: Offline countdown view appears, tape plays after 10 seconds.
4. **Plus user**: No ads, player behaves exactly as before.
5. **Ad failure**: Silent skip — tape plays immediately.
6. **Replay**: Pre-roll plays again, cumulative timer resets.
7. **Background music**: Pauses during ad, resumes after.
8. **ATT prompt**: Appears once, choice persisted.
9. **GDPR (debug)**: UMP form appears with `UMPDebugSettings.geography = .EEA`.
10. **Close during ad**: Player dismisses cleanly, ad torn down.

## Deferred Items

- Custom ad UI overlay (branded badge, countdown) — using SDK default UI for now.
- Post-roll ads — not planned.
- Ad analytics/reporting — post-launch.
- Production GAD App ID and Ad Unit ID — pending Ad Manager approval.
