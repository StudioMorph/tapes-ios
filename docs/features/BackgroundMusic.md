# Background Music (Mubert Integration)

## Summary

AI-generated background music plays simultaneously with tape playback, controlled via a mood picker and volume slider in Tape Settings. Tracks are generated eagerly when a mood is selected, cached per-tape, and can be previewed and regenerated in the settings modal.

## Purpose & Scope

- Allow users to add ambient/mood-based background music to their tapes
- Music is generated via the Mubert AI Music API (royalty-free, DMCA-free)
- Each tape stores its own mood, volume preference, and cached track
- Music plays in sync with the tape's video playback (play/pause/stop)
- Users can preview and regenerate tracks before playing

## Architecture

### Core Services (`Tapes/Core/Music/`)

| File | Role |
|------|------|
| `MubertAPIClient.swift` | API client (actor) — handles track generation requests, response parsing, file download, per-tape caching, and mock fallback |
| `BackgroundMusicPlayer.swift` | `AVAudioPlayer`-based background music controller with sync methods for coordinating with the main `AVPlayer` |
| `TrackGenerationManager.swift` | Observable state machine for the settings UI — drives progress bar, preview playback, and regeneration |

### Model Changes (`Tapes/Models/Tape.swift`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backgroundMusicMood` | `String?` | `nil` | Raw value of `MubertAPIClient.Mood` enum |
| `backgroundMusicVolume` | `Double?` | `nil` | 0.05–1.0, defaults to 0.3 if nil |

Computed helpers: `musicMood` (typed enum), `musicVolume` (Float).

### UI

- **`MoodRowView.swift`**: List-style mood row with icon, label, animated preview button, regenerate button, and green progress bar
- **`TapeSettingsView.swift`**: Integrates `TrackGenerationManager` for per-mood generation, preview, and regeneration
- **Volume slider**: Shown when a mood is selected, 5%–100% range

### Playback Integration (`Tapes/Views/Player/TapePlayerViewModel.swift`)

- `prepare()`: If mood is set, loads cached track or generates one. Uses `pendingPlay` mechanism for race-free sync with video
- `togglePlayPause()`: Syncs background music play/pause with video
- `shutdown()`: Stops background music
- Playback finished: Pauses background music

## Data Flow

```
Tape Settings → user selects mood
                    ↓
                TrackGenerationManager.generate(mood, tapeID)
                    ↓
                MubertAPIClient.generateTrack(mood, tapeID, onProgress)
                    ↓ (API call with polling, or cache hit)
                Track cached at Caches/mubert_tracks/{tapeID}.mp3
                    ↓
                User can preview / regenerate in settings
                    ↓
                Save → mood + volume persisted to Tape model
                    ↓
Playback starts → BackgroundMusicPlayer.prepare(mood, tapeID, volume)
                    ↓ (loads from cache or waits for generation)
                AVAudioPlayer loops alongside AVPlayer
```

## Caching Strategy

- Tracks are cached per-tape at `Caches/mubert_tracks/{tapeID}.mp3`
- 30-second MP3 loops (small file, fast to generate)
- Selecting a different mood clears the previous tape's cache
- Regenerating replaces the existing cached track
- Cache persists across app sessions (cleared by iOS storage management)

## Mubert API

- **Endpoint**: `POST https://music-api.mubert.com/api/v3/public/tracks`
- **Auth**: `customer-id` + `access-token` headers
- **Track duration**: 30s (loops infinitely during playback)
- **Format**: MP3 at 128kbps (~470KB per track)
- **Moods**: Mapped to `playlist_index` values

## Available Moods

None, Chill, Cinematic, Dramatic, Dreamy, Energetic, Epic, Happy, Inspiring, Melancholic, Peaceful, Romantic, Sad, Scary, Upbeat, Uplifting

## Testing

- Select a mood in Tape Settings → green progress bar shows generation
- When complete, tap the waveform icon to preview the track
- Tap the regenerate icon to get a fresh variation
- Switch moods → previous generation cancels, new one starts
- Save → Play the tape → music and video start together
- If track is still generating at playback, loading wheel shows until ready
- Play/pause syncs with the main playback controls

## Dependencies

- `AVFoundation` (Apple framework — `AVAudioPlayer`)
- Mubert AI Music API v3 (REST, no SDK)

## Known Limitations

- Background music is not mixed into exported videos (playback-only for now)
- First generation per mood takes ~15–30s (API processing time)
- Mock fallback generates a 220Hz tone when API returns 401
