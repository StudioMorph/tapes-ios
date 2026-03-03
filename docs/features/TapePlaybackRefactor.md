# Tape Playback Feature - Refactor Summary

## Summary

Complete refactor of the tape playback feature from a 942-line monolithic View into a proper MVVM architecture with 20 targeted improvements covering architecture, HIG compliance, system integration, and memory management.

## Purpose & Scope

The playback feature allows users to preview their tape (a sequence of video and photo clips) with transitions, scrubbing, and clip navigation. This refactor addressed architectural debt, Apple HIG violations, missing system integration, and behavioural bugs without changing the core playback model (per-clip loading with two-player slot transitions).

## Architecture

### Before
- `TapePlayerView.swift` (942 lines) contained 43 `@State` properties and all playback logic
- No ViewModel, untestable
- `PlaybackPreparationCoordinator` existed as unused dead code
- `TapeCompositionBuilder` at 1641 lines handled everything from asset resolution to image encoding

### After
- **`TapePlayerViewModel`** (`@MainActor ObservableObject`): Owns all playback state and logic (~700 lines)
- **`TapePlayerView`**: Thin SwiftUI shell (~160 lines) that binds to the ViewModel
- **`TapeCompositionBuilder`**: Reduced to ~1000 lines (timeline, composition, transforms)
- **`TapeCompositionBuilder+AssetResolution`**: Photos/local asset fetching, URL caching
- **`TapeCompositionBuilder+ImageEncoding`**: Image-to-video frame encoding for export
- Dead `PlaybackPreparationCoordinator` deleted

### Key UI Components
- `PlayerHeader` -- tape title, clip counter, AirPlay picker, close button
- `PlayerControls` -- play/pause/replay, previous/next with disabled states
- `PlayerProgressBar` -- global tape timeline scrubber with 44pt hit target
- `PlayerLoadingOverlay` -- loading spinner and actionable error state (retry/close)
- `PlayerSkipToast` -- auto-dismissing toast for skipped clips
- `AirPlayButton` -- `UIViewRepresentable` wrapping `AVRoutePickerView`

## Data Flow

```
TapePlayerView (SwiftUI shell, ~200 lines)
  ├─ Media layer: playerLayers (dual AVPlayerLayer slots, ignoresSafeArea)
  ├─ Controls overlay (respects safe area)
  │    ├─ headerContainer (PlayerHeader + top gradient scrim)
  │    └─ transportContainer (PlayerProgressBar + PlayerControls + bottom gradient scrim)
  ├─ PlayerSkipToast
  ├─ PlayerLoadingOverlay
  └─ @StateObject TapePlayerViewModel
       ├─ TapeCompositionBuilder (timeline + composition)
       │    ├─ +AssetResolution (Photos, local files, caching)
       │    └─ +ImageEncoding (CGImage → MOV for export)
       ├─ AVPlayer (primary slot)
       ├─ AVPlayer (secondary slot)
       ├─ StillImageVideoCompositor (real-time Ken Burns)
       └─ AVAudioSession (playback category)
```

## Changes by Category

### Architecture (Phases 1-4)
- Extracted `TapePlayerViewModel` with `@Published` properties for UI-bound state
- Deleted unused `PlaybackPreparationCoordinator` (261 lines)
- Split `TapeCompositionBuilder` into 3 files via extensions
- Per-clip playback path already uses custom compositor (Phase 4 was already resolved)

### HIG Compliance (Phases 5-14)
- **Tap to dismiss**: Single tap on video toggles controls on/off
- **Safe area**: Controls overlay respects safe areas naturally (no manual insets); gradient scrims extend behind notch and home indicator via `.ignoresSafeArea(edges:)`
- **Controls layering**: Three-layer architecture -- media (ignores safe area), controls overlay (respects safe area), toasts/loading. Header and transport are separate containers with dedicated gradient scrims for contrast on any footage
- **AirPlay**: Route picker button in the header
- **Reduce Motion**: Slide transitions become crossfade; Ken Burns motion disabled
- **Global scrubber**: Progress bar shows total tape duration; scrubbing navigates across clips
- **Tape title**: Displayed centre-top in the header
- **Replay**: Play button shows `gobackward` icon when tape finishes
- **Error state**: Retry and Close buttons when a loading error occurs
- **Scrubber hit target**: 44pt touch area (16pt visual handle)

### System Integration (Phases 14-16)
- **Audio session**: `.playback` category with `.moviePlayback` mode; audio plays in silent mode
- **Audio interruptions**: Pauses on call/Siri, resumes when interruption ends with `.shouldResume`
- **Route changes**: Pauses when headphones are unplugged
- **Background/foreground**: Pauses on background, resumes on return if was playing
- **Memory management**: LRU cache (10 entries) with eviction on `didReceiveMemoryWarning`

### Behavioural Fixes (Phases 17-21)
- **Auto-hide timer**: Task-based (`Task.sleep`) instead of `Timer.scheduledTimer`; resets on interaction
- **Transition timing**: `withAnimation(_:completion:)` (iOS 17+) instead of `Task.sleep`
- **Gesture conflict**: Swipe `minimumDistance` increased to 20pt; scrubber sits outside swipe zone
- **clipTime clamping**: `min(max(seconds, 0), clipDuration)` prevents scrubber overshoot
- **formatTime**: Supports hours for tapes longer than 60 minutes

## Testing / QA Considerations

- Verify playback of mixed video/photo tapes (5+ clips)
- Test AirPlay by connecting to an Apple TV or HomePod
- Test Reduce Motion in Settings > Accessibility > Motion
- Test silent mode (physical switch) -- audio should still play
- Test headphone disconnect -- playback should pause
- Test backgrounding during playback -- should pause and resume
- Test large tapes (100+ clips) -- memory should stay bounded
- Test scrubbing across clip boundaries on the global progress bar
- Test replay button at end of tape
- Test error state with an inaccessible clip (delete from Photos mid-play)
