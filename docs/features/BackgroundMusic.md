# Background Music (Mubert Integration)

## Summary

AI-generated background music plays simultaneously with tape playback, controlled via a mood picker and volume slider in Tape Settings.

## Purpose & Scope

- Allow users to add ambient/mood-based background music to their tapes
- Music is generated via the Mubert AI Music API (royalty-free, DMCA-free)
- Each tape stores its own mood and volume preference
- Music plays in sync with the tape's video playback (play/pause/stop)

## Architecture

### Core Services (`Tapes/Core/Music/`)

| File | Role |
|------|------|
| `MubertAPIClient.swift` | API client (actor) — handles track generation requests, response parsing, file download, and mock fallback |
| `BackgroundMusicPlayer.swift` | `AVAudioPlayer`-based background music controller with sync methods for coordinating with the main `AVPlayer` |

### Model Changes (`Tapes/Models/Tape.swift`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backgroundMusicMood` | `String?` | `nil` | Raw value of `MubertAPIClient.Mood` enum |
| `backgroundMusicVolume` | `Double?` | `nil` | 0.05–1.0, defaults to 0.3 if nil |

Computed helpers: `musicMood` (typed enum), `musicVolume` (Float).

### UI (`Tapes/Views/TapeSettingsView.swift`, `Tapes/Components/MoodOptionCell.swift`)

- **Mood picker**: 3-column grid of 16 moods (None, Chill, Cinematic, Dramatic, etc.)
- **Volume slider**: Shown when a mood is selected, 5%–100% range

### Playback Integration (`Tapes/Views/Player/TapePlayerViewModel.swift`)

- `prepare()`: If mood is set, generates/downloads a track and prepares `AVAudioPlayer`
- `togglePlayPause()`: Syncs background music play/pause with video
- `shutdown()`: Stops background music
- Playback finished: Pauses background music

## Data Flow

```
Tape Settings → mood + volume saved to Tape model
                    ↓
Playback starts → TapePlayerViewModel.prepare()
                    ↓
                MubertAPIClient.generateTrack(mood, duration)
                    ↓ (API call or mock fallback)
                BackgroundMusicPlayer.prepare(url, volume)
                    ↓
                AVAudioPlayer loops alongside AVPlayer
```

## Mubert API

- **Endpoint**: `POST https://music-api.mubert.com/api/v3/public/tracks`
- **Auth**: `customer-id` + `access-token` headers
- **Status**: Credentials pending activation; mock fallback (silent WAV) active until resolved
- **Moods**: Mapped to `playlist_index` values (placeholder mapping until API docs confirm exact indices)

## Available Moods

None, Chill, Cinematic, Dramatic, Dreamy, Energetic, Epic, Happy, Inspiring, Melancholic, Peaceful, Romantic, Sad, Scary, Upbeat, Uplifting

## Testing

- Select a mood in Tape Settings → Save → Play the tape
- Background music should start with the first clip
- Play/pause syncs with the main playback controls
- Closing the player stops background music
- Volume slider adjusts background music level relative to tape audio
- With API not yet active, a silent WAV is generated as mock fallback

## Dependencies

- `AVFoundation` (Apple framework — `AVAudioPlayer`)
- Mubert AI Music API v3 (REST, no SDK)

## Known Limitations

- Mubert API credentials are pending activation (401 Unauthenticated)
- `playlist_index` mapping is placeholder until full API docs are accessible
- Background music is not mixed into exported videos (playback-only for now)
- No offline caching of previously generated tracks beyond the session cache
