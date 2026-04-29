# Background Music (Mubert Integration)

## Summary

AI-generated and library-sourced background music plays simultaneously with tape playback. Three entry methods via a unified sheet: **12K Library** (pre-made tracks), **Moods** (AI-generated mood-based), and **AI Prompt** (text-to-music). Tracks are cached per-tape and sync with video playback.

## Purpose & Scope

- Allow users to add ambient/mood-based background music to their tapes
- Music sourced via the Mubert AI Music API (royalty-free, DMCA-free)
- Three selection methods: browse the 12K library, pick a mood, or describe a vibe via text prompt
- Each tape stores its source, volume preference, wave colour, and cached track
- Music plays in sync with the tape's video playback (play/pause/stop)
- Music is included in exported videos

## Architecture

### Core Services (`Tapes/Core/Music/`)

| File | Role |
|------|------|
| `MubertAPIClient.swift` | API client (actor) — handles track generation (mood + prompt), library track download, response parsing, file caching, and polling |
| `BackgroundMusicPlayer.swift` | `AVAudioPlayer`-based background music controller with sync methods for coordinating with the main `AVPlayer` |
| `TrackGenerationManager.swift` | Observable state machine for the Moods tab — drives progress bar, preview playback, and regeneration |
| `MusicPreviewManager.swift` | Shared `ObservableObject` managing a single active music preview across all `TapeCardView` instances |

### Backend Routes (`tapes-api/src/routes/music.ts`)

| Route | Purpose |
|-------|---------|
| `POST /music/generate` | Generate a track from mood (`mood_playlist`) or text prompt (`prompt`), with configurable `intensity` and `duration` |
| `GET /music/tracks/:id` | Poll for track generation status |
| `GET /music/library/params` | Fetch available filter categories (genres, moods, activities, BPM) for the 12K library |
| `GET /music/library/tracks` | Browse/filter library tracks with pagination |

### Model Changes (`Tapes/Models/Tape.swift`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backgroundMusicMood` | `String?` | `nil` | Mood raw value, `"library:{trackID}"`, or `"prompt"` |
| `backgroundMusicVolume` | `Double?` | `nil` | 0.05–1.0, defaults to 0.3 if nil |
| `waveColorHue` | `Double?` | `nil` | Random 0–1 hue for the animated wave visualisation |

Computed helpers: `musicMood` (typed enum), `musicVolume` (Float), `hasBackgroundMusic` (true if any source is set).

### UI

- **`BackgroundMusicSheet.swift`**: Full-height sheet with segmented control: 12K Library / Moods / AI Prompt
- **`LibraryBrowserView.swift`**: Filter pills, track list with metadata tags, inline preview via `AVPlayer`, "Use this track" download button, pagination
- **`BackgroundMusicPickerView.swift`**: Mood grid with generation, preview, volume control (reused from existing implementation)
- **`AIPromptMusicView.swift`**: Multi-line text prompt, quick tags, duration slider (15–90s), energy picker (Low/Medium/High), generate button with progress
- **`MusicWaveView.swift`**: Animated Canvas-based wave visualisation with 12 layered paths, audio-reactive spikes, speckle particles, and per-tape random colouring
- **`MoodRowView.swift`**: List-style mood row with icon, label, animated preview button, regenerate button, and progress bar

### Entry Points

- **Music bar on TapeCardView**: Music note + chevron button opens `BackgroundMusicSheet`
- **Waveform icon on TapeCardView**: Previews cached track via `MusicPreviewManager`
- **Tape Settings**: Existing mood picker (retained for backwards compatibility)

### Playback Integration (`Tapes/Views/Player/TapePlayerViewModel.swift`)

- `prepare()`: If `hasBackgroundMusic`, loads cached track or generates one (mood-based only). Library/prompt tracks must already be cached
- `togglePlayPause()`: Syncs background music play/pause with video
- `shutdown()`: Stops background music
- Playback finished: Pauses background music

### Export Integration (`Tapes/Export/TapeExporter.swift`)

- If `tape.hasBackgroundMusic`, mixes the cached track into the exported video

## Data Flow

```
BackgroundMusicSheet → user selects source
                            ↓
    Tab 1 (Library): Browse → Preview → "Use this track" → download MP3
    Tab 2 (Moods):   Select mood → generate via API → cache
    Tab 3 (Prompt):  Type description → generate via API → poll → cache
                            ↓
    Track stored at Application Support/mubert_tracks/{tapeID}.mp3
    tape.backgroundMusicMood = "library:{id}" | "{mood}" | "prompt"
    tape.backgroundMusicPrompt = "{prompt text}"   // prompt tracks only
    tape.waveColorHue assigned if nil
                            ↓
Playback starts → BackgroundMusicPlayer.prepare(mood, tapeID, volume)
                            ↓ (loads from cache)
                AVAudioPlayer loops alongside AVPlayer
```

## Storage Strategy

- Committed tracks live at `Application Support/mubert_tracks/{tapeID}.mp3`.
  This is durable storage — iOS does not purge it the way it can purge
  `Caches/`. Earlier builds wrote to `Caches/`, which silently broke the
  "Use this track" promise across launches; a one-shot migration on
  first launch of this build moves any leftover legacy files into the
  new location.
- The `mubert_tracks` directory is marked
  `isExcludedFromBackup = true`. Audio is regenerable from the server
  and we don't want it bloating iCloud backups.
- 30-second MP3 loops for mood/prompt tracks (~470KB).
- Library tracks are variable duration.
- Selecting a different source for a tape clears its previous file.
- Regenerating replaces the existing file.
- Scratch (provisional) tracks generated by the AI Prompt tab live in
  `tmp/mubert_scratch/{uuid}.mp3` until the user taps **Use this
  track**, at which point they're committed into the durable per-tape
  slot.

## Mubert API

- **Track generation**: `POST /music/generate` (proxied through Tapes API)
- **Library params**: `GET /music/library/params` (genres, moods, activities, BPM)
- **Library tracks**: `GET /music/library/tracks` (filterable, paginated, with stream URLs)
- **Auth**: `customer-id` + `access-token` headers (server-side only)
- **Track duration**: 30s default (mood/prompt), variable (library)
- **Format**: MP3 at 128kbps

## Available Moods

None, Chill, Cinematic, Dramatic, Dreamy, Energetic, Epic, Happy, Inspiring, Melancholic, Peaceful, Romantic, Sad, Scary, Upbeat, Uplifting

## Testing

- Tap music note + chevron on any non-empty tape → sheet opens
- **12K Library tab**: Filters load, tracks list, tap play to stream, tap "Use this track" to assign
- **Moods tab**: Select mood → generation progress → preview → regenerate
- **AI Prompt tab**: Type description, adjust duration/energy, generate → progress → assigned
- All three sources: play the tape → music and video start together
- Export with background music → music mixed into output
- Preview stops when: switching tapes, opening modals, starting playback, backgrounding the app

## Dependencies

- `AVFoundation` (Apple framework — `AVAudioPlayer`, `AVPlayer`)
- Mubert AI Music API v3 (REST, no SDK)

## Known Limitations

- Library tracks don't have human-readable names — display names are derived from metadata (key, BPM, intensity)
- Library track artwork is not available from the API
- First generation per mood/prompt takes ~15–30s (API processing time)
- Library/prompt tracks require the Mubert Startup plan or above
