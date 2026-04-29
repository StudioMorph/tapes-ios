# Background Music Modal — Implementation Plan

## Summary

New full-sheet modal accessible from the music bar on every `TapeCardView`. Three tabs via segmented control: **12K Library**, **Moods**, **AI Prompt**. Replaces the current entry point for background music selection while keeping the existing mood picker in Tape Settings temporarily.

---

## 1. Backend — New Proxy Routes

All Mubert credentials stay on the Worker. iOS never touches them.

### 1a. `GET /music/library/params`

Proxies `GET https://music-api.mubert.com/api/v3/public/music-library/params`.

- Passes through query params for cross-filtering (e.g. `?genres=Lo-fi&bpm=120`)
- Returns filter categories: genres, moods, activities, BPM, themes — each with track counts
- iOS uses this to populate the filter pills and show "248 tracks" counts

### 1b. `GET /music/library/tracks`

Proxies `GET https://music-api.mubert.com/api/v3/public/music-library/tracks`.

- Passes through filter query params (`genres`, `moods`, `activities`, `bpm`, `duration`)
- Supports pagination: `limit` (default 50) and `offset`
- Each track in response has: `id`, `session_id`, `playlist_index`, `bpm`, `key`, `duration`, `intensity`, `mode`, and `generations[0].url` (direct MP3 download link)
- iOS streams/plays the track URL for preview, downloads on "Use this track"

### 1c. Update `POST /music/generate`

Extend the existing endpoint to accept text-to-music requests:

- New optional field: `prompt` (string, max 200 chars)
- When `prompt` is present, omit `playlist_index` — Mubert uses the prompt for tag-based generation
- New optional field: `intensity` (string: "low", "medium", "high") — maps to Energy picker
- Widen duration clamp from max 60s to max 90s
- Validation: exactly one of `mood_playlist` or `prompt` must be present

Polling via existing `GET /music/tracks/:id` — no changes needed.

---

## 2. iOS — Networking Layer

### 2a. `TapesAPIClient` — New Methods

```swift
// 12K Library
func fetchLibraryParams(filters: [String: String]) async throws -> [LibraryParam]
func fetchLibraryTracks(filters: [String: String], offset: Int, limit: Int) async throws -> LibraryTracksResponse

// Text-to-Music (extends existing generate)
func generateMusicFromPrompt(prompt: String, duration: Int, intensity: String) async throws -> MusicGenerateResponse
```

### 2b. New Response Models

```swift
struct LibraryParam: Decodable {
    let param: String
    let values: [ParamValue]
}
struct ParamValue: Decodable {
    let value: String
    let tracksCount: Int
}
struct LibraryTrack: Decodable, Identifiable {
    let id: String
    let bpm: Int?
    let key: String?
    let duration: Int
    let intensity: String
    let generations: [Generation]
}
struct LibraryTracksResponse: Decodable {
    let data: [LibraryTrack]
    let meta: PaginationMeta
}
```

### 2c. `MubertAPIClient` — New Methods

- `fetchLibraryParams(filters:api:)` — wraps the API call
- `fetchLibraryTracks(filters:offset:limit:api:)` — wraps with pagination
- `generateFromPrompt(prompt:duration:intensity:tapeID:api:onProgress:)` — same poll-and-download pattern as existing `generateTrack`

---

## 3. iOS — UI

### 3a. `BackgroundMusicSheet` (new)

Full-height sheet presented from `TapeCardView` when tapping:
- Music note + chevron
- The wave itself

Structure:
- Navigation title: "Background music"
- Segmented control (iOS native `Picker(.segmented)`): **12k Library** / **Moods** / **AI prompt**
- Content switches based on selected segment

### 3b. Tab 1: `LibraryBrowserView` (new)

- **Filter pills** — horizontal `ScrollView` of capsule buttons. First load fetches `/music/library/params` to get available genres, moods, activities, BPM values. Tapping a pill toggles it as an active filter and refetches tracks.
- **Track count + sort** — "248 tracks" label from `meta.total`. Sort toggle (Popular/Recent) if API supports it, otherwise static.
- **Track list** — `LazyVStack` of track rows. Each row shows:
  - Coloured waveform icon (derived from genre)
  - Track name (we'll need to derive/generate names since Mubert tracks don't have human-readable names — use playlist category + BPM + key as fallback, or just "Track #N")
  - Tags: genre, mood, BPM, duration
  - Play/pause button — streams the MP3 URL directly via `AVPlayer`
- **Expanded state** — when a track is selected and playing:
  - Progress bar showing current playback position
  - "Use this track" button — downloads the MP3 to the tape's cache directory and assigns it
- **Pagination** — load more tracks when scrolling near the bottom

### 3c. Tab 2: `MoodPickerView` (existing, moved)

- Reuse the content from `BackgroundMusicPickerView`
- Same mood grid, generation, preview, volume slider
- Don't delete from Tape Settings yet

### 3d. Tab 3: `AIPromptView` (new)

- **Text field** — "Describe the vibe" with multi-line `TextEditor`, 200 char limit
- **Quick tags** — horizontal wrapped layout of tappable pills: Lo-fi, Cinematic, Ambient, Upbeat, Chill, Electronic, Jazz, Dreamy. Tapping appends/removes the tag from the text field
- **Duration slider** — 15s to 90s, default 30s, labels at both ends, current value displayed
- **Energy picker** — three-segment picker: Low / Medium / High, default Medium
- **"Generate track" button** — calls `generateFromPrompt`, shows progress (reuse existing generation UI pattern), then downloads and assigns to tape
- **"Powered by Mubert AI"** — small credit text below button

### 3e. Track Assignment

When a track is selected (from Library or AI Prompt):
1. Download MP3 to `mubert_tracks/{tapeID}.mp3` (same cache as current mood tracks)
2. Clear any existing cached track for the tape
3. Set `tape.backgroundMusicMood` to a new value indicating the source (e.g. `"library:{trackID}"` or `"prompt:{truncatedPrompt}"`)
4. Assign `tape.waveColorHue` if not already set
5. Persist via `tapeStore.updateTape(tape)`
6. Dismiss the sheet

---

## 4. Tape Model Considerations

The current `backgroundMusicMood` field stores a `Mood.rawValue` string. Library and AI tracks aren't mood-based. Options:

**Recommended:** Add a new field `backgroundMusicSource` (`String?`) that stores the source type:
- `nil` or `"mood:{rawValue}"` — existing mood-based track
- `"library:{trackID}"` — 12K library track
- `"prompt"` — AI-generated from prompt

This avoids breaking the existing mood flow. The `musicMood` computed property continues working for mood-based tracks. A new `hasBackgroundMusic` computed property returns true if any source is set.

---

## 5. Execution Order

1. **Backend**: Add the 3 route changes (library/params, library/tracks, extend generate) — deploy
2. **iOS networking**: Add API client methods and response models
3. **iOS UI**: Build `BackgroundMusicSheet` shell with segmented control
4. **Tab 2 (Moods)**: Move existing picker content into the new sheet
5. **Tab 1 (12K Library)**: Build `LibraryBrowserView` with filters, track list, preview, assignment
6. **Tab 3 (AI Prompt)**: Build `AIPromptView` with prompt input, tags, duration, energy, generation
7. **Wire entry point**: Connect music note/chevron and wave taps to present the sheet
8. **Test all flows**, commit incrementally

---

## 6. Risks & Open Questions

- **Track names**: Mubert library tracks don't have human-readable names. We'll need to derive display names from metadata (genre + mood + BPM) or generate them. The wireframe shows names like "Coastal Drift" — those would need to come from Mubert or be invented client-side.
- **Library track expiry**: Library track URLs may expire (like generated tracks). Need to check `expired_at` and handle re-fetching.
- **Paywall gating**: 12K Library and AI Prompt are Tapes Plus features. Paywall enforcement needed before generation/selection for free users.
- **Mubert plan limits**: Current plan may have generation limits. Need to confirm our Mubert subscription tier supports library access (requires Startup plan or above per their pricing page).
