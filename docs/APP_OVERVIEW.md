# TAPES — Complete App Overview

This document describes every feature, flow, and system in the Tapes iOS app as of April 2026.

---

## 1. What is Tapes?

Tapes is a native iOS app for creating, playing, and sharing short-form video reels. A **Tape** is an ordered collection of **Clips** — videos, photos, and Live Photos — that plays as a continuous reel with transitions, motion effects, and optional AI-generated background music. Users can share tapes with others (view-only or collaborative), export them as a single merged video, and organise them into Photos library albums.

**Target:** iOS 18.2+, iPhone and iPad, Swift 5, SwiftUI + MVVM, Swift Concurrency.

**Stack:**
- **Frontend:** SwiftUI, AVFoundation, Photos framework, StoreKit 2
- **Backend:** Cloudflare Workers (TypeScript), D1 (SQLite), R2 (object storage)
- **Auth:** Sign in with Apple → server-issued JWT
- **Music:** Mubert API (AI-generated background tracks)
- **Push:** APNs via HTTP/2 from Cloudflare Workers

---

## 2. Core Data Model

### Tape

A tape is the top-level container. Key properties:

| Property | Description |
|----------|-------------|
| `id` | Stable UUID |
| `title` | User-editable name (inline editing on tape cards) |
| `orientation` | `portrait` (9:16) or `landscape` (16:9) — the tape's intended framing |
| `scaleMode` | `fit` (letterbox) or `fill` (crop) — default for all clips |
| `transition` | Default transition type: `none`, `crossfade`, `slideLR`, `slideRL`, `randomise` |
| `transitionDuration` | Seconds (0.1–2.0) for the default transition |
| `seamTransitions` | Per-boundary overrides — dictionary keyed by `leftClipID_rightClipID` |
| `clips` | Ordered array of `Clip` structs |
| `backgroundMusicMood` | Mubert mood string (e.g. "cinematic", "dreamy") or nil |
| `backgroundMusicVolume` | 0.0–1.0 (default 0.3) |
| `exportOrientation` | `auto` (majority of clips), `portrait`, or `landscape` |
| `blurExportBackground` | When true, letterboxed content has a blurred background instead of black bars |
| `livePhotosAsVideo` | Tape-level default: play Live Photos as video clips (default true) |
| `livePhotosMuted` | Tape-level default: mute Live Photo audio (default true) |
| `albumLocalIdentifier` | Links to a Photos library album for this tape |
| `shareInfo` | If non-nil, the tape is shared (contains `shareId`, `remoteTapeId`, `mode`, `ownerName`, `expiresAt`) |
| `lastUploadedClipCount` | Tracks how many clips were on the server after the last upload — drives the upload badge |
| `isCollabTape` | If true, this tape lives in the Collab tab and can only be shared as collaborative |
| `hasUnseenContent` | Set when new clips are downloaded from another user; cleared when the tape is played |

**Computed:**
- `duration` — sum of all clip durations + transition overlaps
- `pendingUploadCount` — `max(0, localClipCount - lastUploadedClipCount)` — how many new clips need uploading
- `isShared` — `shareInfo != nil`
- `musicMood` / `musicVolume` — resolved from raw strings/doubles

### Clip

A clip is a single media unit within a tape:

| Property | Description |
|----------|-------------|
| `id` | UUID |
| `assetLocalId` | `PHAsset.localIdentifier` when sourced from Photos library |
| `localURL` | Sandbox file path for imported videos |
| `imageData` | JPEG bytes for non-library images |
| `clipType` | `.video` or `.image` (Live Photos are `.image` with `isLivePhoto = true`) |
| `duration` | Source duration (seconds) |
| `thumbnail` | JPEG thumbnail data (stripped from JSON, stored in `clip_media/` files) |
| `rotateQuarterTurns` | 0–3 (0°, 90°, 180°, 270°) |
| `overrideScaleMode` | Per-clip fit/fill override |
| `trimStart` / `trimEnd` | Seconds trimmed from source (video only) |
| `motionStyle` | Still-image motion: `none`, `kenBurns`, `pan`, `zoomIn`, `zoomOut`, `drift` |
| `imageDuration` | Display duration for stills (default 3–4 seconds) |
| `isLivePhoto` | True if this clip is a Live Photo |
| `livePhotoAsVideo` / `livePhotoMuted` | Per-clip overrides of tape defaults |
| `volume` | Clip audio level (nil = full volume) |
| `musicVolume` | Background music level during this clip (nil = tape default) |
| `isPlaceholder` | Synthetic clip for sync/UI — never persisted |
| `isSynced` | True if this clip has been uploaded to the server |

**Note on Live Photos:** The app model uses `ClipType.image` + `isLivePhoto = true`. The server manifest uses a separate string `"live_photo"`. The paired video component is extracted on-demand from the Photos library using `PHAssetResourceManager` — it is never stored inline in the clip.

### Persistence

- **Primary:** `tapes.json` in the Documents directory, encoding `[Tape]`
- **Blob offload:** Thumbnails and image data are stripped from clips before JSON serialisation and stored as `{clipID}_thumb.jpg` and `{clipID}_image.dat` in `Documents/clip_media/`
- **Photos integration:** Clips reference `PHAsset` identifiers; tapes reference `PHCollectionList` album identifiers
- **No Core Data** — all JSON + file-based

---

## 3. Navigation Structure

Four-tab layout:

| Tab | View | Purpose |
|-----|------|---------|
| **My Tapes** | `TapesListView` | Personal tapes the user created. View-only sharing only. |
| **Shared** | `SharedTapesView` | View-only tapes received from others via share links |
| **Collab** | `CollabTapesView` | Collaborative tapes — both owned and received. Bidirectional sync. |
| **Account** | `AccountTabView` | Sign in, appearance, subscription, about |

Each tab has its own `NavigationStack`. The `NavigationCoordinator` handles deep links and tab switching.

---

## 4. Camera & Media Capture

### In-App Camera

- Built on `AVCaptureSession` via `CaptureService` — supports back cameras (triple/dual/wide), optional microphone
- **Photo mode:** `AVCapturePhotoOutput` with optional Live Photo (paired `.mov` file)
- **Video mode:** `AVCaptureMovieFileOutput` with stabilisation when supported
- UI: tap-to-focus, pinch zoom, flash/torch, timer (3s/10s), Live Photo toggle
- Accelerometer-driven `DeviceOrientationObserver` ensures correct video rotation
- Captured items appear in a session carousel for review before committing

### Gallery Import

- `PHPickerConfiguration` with ordered multi-select, images + videos
- `resolvePickedMedia` resolves each picked item: videos get duration + asset ID; images get high-quality thumbnail + Live Photo detection
- `MediaImportCoordinator` builds `Clip` objects from resolved media

### How Clips Enter a Tape

1. User taps the FAB (camera or gallery mode) on a tape card
2. Media is captured or picked
3. Assets are saved to Photos library (camera captures) or referenced by `assetLocalId` (gallery)
4. `Clip` objects are created and inserted into the tape at the current carousel position
5. Clips are associated with the tape's Photos album via `TapeAlbumService`
6. Thumbnails are generated asynchronously

### The FAB (Floating Action Button)

The red circular button at the centre of each tape card. Horizontal swipe cycles between three modes:
- **Camera** — opens the full-screen camera
- **Gallery** — opens PHPicker for importing from the photo library
- **Transition** — opens the seam transition editor for the boundary between the two adjacent clips

---

## 5. Clip Editing

### Video Trimming (`ClipTrimView`)

- Available for video clips only
- Displays a filmstrip timeline (~15 frame thumbnails) with draggable left/right handles
- Playback loops within the trimmed region
- `trimStart` and `trimEnd` stored on the clip; `trimmedDuration = duration - trimStart - trimEnd`
- Background music plays synced during trim preview
- Volume controls for clip audio and music

### Image/Live Photo Settings (`ImageClipSettingsView`)

- **Motion style:** None, Ken Burns, Pan, Zoom In, Zoom Out, Drift
- **Display duration:** 3–10 seconds (disabled when Live Photo plays as video)
- **Live Photo toggle:** Play as video clip or as a static image
- **Volume controls:** Clip audio and background music levels (per-clip overrides)

### Per-Clip Properties

- Rotation (quarter turns)
- Fit/fill override
- All settings persist to the clip model and are reflected in both playback and export

---

## 6. Tape Settings (`TapeSettingsView`)

Accessed via the settings icon on each tape card:

- **Transitions:** Default transition type and duration for the tape
- **Background music:** Mood picker (16 AI-generated moods via Mubert) with preview playback
- **Live Photos:** Tape-level defaults for video/muted mode; "Reset all clips to defaults" clears per-clip overrides
- **Export:** Orientation (auto/portrait/landscape), background blur toggle, "Save and Merge" button
- **Delete tape:** With confirmation

### Seam Transitions (`SeamTransitionView`)

Per-boundary transition overrides between specific clips:
- Accessed by swiping the FAB to "Transition" mode when positioned between two clips
- Styles: none, crossfade, slide L→R, slide R→L (randomise is tape-level only)
- Duration slider (0.1–2.0s)
- "Use Tape Default" clears the override

---

## 7. Playback

### Architecture

- **Dual-player system:** Two `AVPlayer` instances (`primary` and `secondary`) with layered `AVPlayerLayer`s
- **Sequential clips:** Each clip is a separate `AVPlayerItem`, not one monolithic composition. Items are cached (LRU, capacity 10) with sequential preloading of upcoming clips.
- **Still images:** Converted to playable items using `StillImageVideoCompositor` — a custom `AVVideoCompositing` implementation that draws frames with Ken Burns / motion effects in real-time

### Transitions (In Playback)

- **Crossfade:** Both players run simultaneously; opacity crossfade between layers
- **Slide:** Both players run; horizontal offset animation (one slides out, next slides in)
- **Audio crossfade:** `AVPlayer.volume` is ramped between active and inactive players over 24 steps
- **Swipe-driven:** Users can swipe to interactively transition between clips
- **Reduce Motion:** Slide transitions downgrade to crossfade; Ken Burns motion freezes

### Background Music

- AI-generated tracks via **Mubert API** — 16 mood categories
- Tracks are generated per-tape, cached as MP3 in `Caches/mubert_tracks/{tapeID}.mp3`
- Playback via a separate `AVAudioPlayer` (infinite loop) synced with the video player
- Per-clip music volume levels supported (ducking/boosting at clip boundaries)
- Audio session: `.playback` category with `.mixWithOthers`

### Mubert Moods

`chill`, `cinematic`, `dramatic`, `dreamy`, `energetic`, `epic`, `happy`, `inspiring`, `melancholic`, `peaceful`, `romantic`, `sad`, `scary`, `upbeat`, `uplifting`, and `none`.

---

## 8. Export

### How It Works

1. `ExportCoordinator` is triggered from tape settings ("Save and Merge") or the share modal
2. `TapeExportSession` builds a full `AVMutableComposition`:
   - Video clips alternate across two tracks (for transition overlap)
   - Still images are pre-rendered as short H.264 `.mov` files (1 fps)
   - Transitions are baked into `AVMutableVideoComposition` instructions (crossfade via opacity ramps, slide via transform ramps)
   - Ken Burns / motion effects are applied as transform ramps in the video composition
3. Background music is looped for the full duration with per-clip volume ramps and a 1.5s fade-out at the end
4. **Reader/writer pipeline:** `AVAssetReader` + `AVAssetReaderVideoCompositionOutput` + `AVAssetWriter`
5. **Output:** HEVC at ~10 Mbps, AAC audio at 128 kbps / 44.1 kHz, saved to temp file then Photos library
6. Resolution: 1080×1920 (portrait) or 1920×1080 (landscape)

### Background Export

- iOS 26+: `BGContinuedProcessingTask` with optional GPU resources
- Pre-iOS 26: `UIApplication.beginBackgroundTask` fallback
- Local notification on completion when app is in background
- Progress tracking: 0–95% from video PTS, last 5% reserved for finalisation

### Blurred Background

When `blurExportBackground` is enabled and clips don't fill the frame (letterboxing), a `BlurredBackgroundCompositor` renders a blurred, scaled copy of the clip behind the letterboxed content — no black bars.

---

## 9. Drag, Drop, and Reordering

### Floating Clips

- **Long press** on a clip in jiggle mode lifts it from the tape
- The clip follows the user's finger as a floating overlay
- **Drop targets:** FAB positions (gaps between clips) on any tape, including other tapes
- On release, the clip is removed from its source tape and inserted at the target position

### Jiggle Mode

- Activated by long press on the clip carousel
- Clips animate with sinusoidal motion (like iOS home screen icon rearranging)
- "Done" button in toolbar exits jiggle mode
- Tab switching automatically exits jiggle mode and returns any floating clip

---

## 10. Photos Library Integration

### Tape Albums (`TapeAlbumService`)

- Each tape can be associated with a Photos library album named after the tape title
- Albums are created on first clip addition and reused thereafter
- `associateClipsWithAlbum` adds `PHAsset`s to the album after every capture/import
- Albums are renamed when the tape title changes (subject to Photos permission level)
- Albums can be deleted with the tape (feature-flagged)

### Asset References

- Clips reference Photos assets via `assetLocalId` (`PHAsset.localIdentifier`)
- The app never copies media files locally for library-sourced clips — it reads from Photos on demand
- For shared/downloaded tapes, clips are saved to Photos and then referenced by their new `assetLocalId`

---

## 11. Sharing — View-Only

### How It Works

1. **Owner** opens the share modal on a tape in "My Tapes"
2. First share triggers an upload: `ShareUploadCoordinator` creates a server tape record (`POST /tapes`), then uploads each clip to R2 via presigned URLs (`POST /clips` → `PUT` to R2 → `POST /uploaded`)
3. Owner gets a share link: `https://api.tapes.app/t/{shareId}`
4. **Recipient** taps the link → Universal Link / deep link resolves → app calls `GET /share/{shareId}` → fetches manifest → downloads clips from R2 → saves to Photos → creates a local `Tape` with `ShareInfo`
5. Tape appears in the recipient's **Shared** tab

### Delta Updates

- If the owner adds clips after sharing, `lastUploadedClipCount` tracks the delta
- An **upload badge** (`SyncBadge`, direction `.upload`) appears on the tape card in "My Tapes"
- Owner taps the badge → "Update everyone's tape" confirmation → delta upload → `POST /sync-push` notifies recipients
- Recipients see a **download badge** (`SyncBadge`, direction `.download`) on the tape in the Shared tab
- Tapping the badge downloads only the new clips (delta based on clip IDs)

### View-Only Rules

- Only the owner can add clips
- Recipients can view, play, and export but cannot contribute
- Re-sharing by recipients is not supported

---

## 12. Sharing — Collaborative

### How It Works

1. **Owner** creates a tape in the **Collab** tab (marked `isCollabTape = true`)
2. Owner shares via the collab share link — recipients join as collaborators
3. Tape appears in the recipient's **Collab** tab
4. **Both owner and recipients** can add clips via camera or gallery
5. New clips are uploaded as contributions (`ShareUploadCoordinator.contributeClips`)
6. A **sync badge** (`SyncBadge`, direction `.sync`) appears when there are pending uploads or downloads
7. Tapping the sync badge runs a bidirectional sync: upload new local clips first, then download new remote clips

### Collab Rules

- All contributions land on the same server tape
- Each contribution resets the 7-day R2 asset retention timer
- The owner's clips are uploaded via `ensureTapeUploaded` (full upload or delta)
- Recipients' clips are uploaded via `contributeClips` (additive only)
- `isSynced` on each clip tracks whether it has been uploaded

---

## 13. The Four Share Links

Every tape has four permanent share links:

| Variant | Role | Protection |
|---------|------|------------|
| `view_open` | View-only | Anyone with the link |
| `view_protected` | View-only | Email allow-list |
| `collab_open` | Collaborative | Anyone with the link |
| `collab_protected` | Collaborative | Email allow-list |

- "Secured by email" toggle switches between `*_open` and `*_protected` variants
- Protected links require the recipient's email to be explicitly invited via `POST /collaborators`
- All four IDs are minted on tape creation and back-filled for older tapes
- Tapes in "My Tapes" can only use view variants; tapes in "Collab" can only use collab variants

---

## 14. Sync Architecture (Event-Driven)

### Three Layers

1. **Push notifications (real-time):** When a clip is uploaded (`POST /clips/:id/uploaded`), the server sends an APNs push with `content-available: 1` to all other participants. iOS handles it in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and triggers an immediate sync status check. Badges update within seconds.

2. **Lightweight status check (fallback):** `POST /sync/status` accepts an array of tape IDs and returns pending download counts from the server's `clip_download_tracking` table. One request replaces N manifest fetches. Runs every 5 minutes as a safety net for missed pushes.

3. **Full manifest (download-only):** `GET /tapes/:id/manifest` is only called when the user actually taps a badge to download. Never used for badge computation.

### SyncBadge Behaviour

| Tab | Badge Type | Trigger |
|-----|-----------|---------|
| My Tapes | Upload badge (blue, arrow up) | Local clips exceed `lastUploadedClipCount` |
| Shared | Download badge (red, arrow down) | Server has clips the user hasn't downloaded |
| Collab | Sync badge (bidirectional) | Pending uploads + pending downloads combined |

### Unseen Content Indicator (Blue Dot)

When new clips are downloaded from another user (via `mergeClipsIntoSharedTape`), the tape's `hasUnseenContent` flag is set to `true`. A small blue dot (8pt circle, `Tokens.Colors.systemBlue`) appears inline before the tape title in `TapeCardView`, separated by 4pt from the title text. The dot disappears as soon as playback is triggered for that tape, clearing the flag via `clearUnseenContent(for:)`.

### Tab Badges

- The **Shared** tab shows a badge count of view-only tapes with pending downloads
- The **Collab** tab shows a badge count of collaborative tapes with pending changes
- App icon badge is set to 1 by push notifications; cleared when entering Shared or Collab tab

---

## 15. Push Notifications

### Infrastructure

- APNs entitlement (`aps-environment: development`)
- `remote-notification` background mode in `Info.plist`
- Device token registered via `PUT /users/me/device-token`
- Server sends pushes using native `crypto.subtle` ECDSA JWT (ES256) — no third-party library

### Push Types

| Event | Payload | Behaviour |
|-------|---------|-----------|
| Clip uploaded | Alert + `content-available: 1` + `tape_id` + `action: sync_update` | Notification banner shown; app wakes in background to update sync badges |
| Sync push (manual) | Alert + `tape_id` + `share_id` | Notification banner; tap navigates to Shared tab |

### Background Handling

- `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` delegates to `PushNotificationManager.handleBackgroundPush`
- Push with `tape_id` triggers `TapeSyncChecker.updateFromPush` (instant badge bump) + `refresh` (authoritative status check)
- `willPresent` (foreground) also triggers sync update for `sync_update` actions
- `didReceive` (user tap) navigates via `NavigationCoordinator`

---

## 16. Backend API (Cloudflare Workers + D1 + R2)

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/auth/apple` | Exchange Apple identity token for server JWT |
| `POST` | `/tapes` | Create or re-resolve a tape record |
| `GET` | `/tapes/:id` | Get tape metadata |
| `DELETE` | `/tapes/:id` | Delete tape and all R2 assets |
| `GET` | `/tapes/:id/validate` | Validate tape access + pending downloads |
| `GET` | `/tapes/:id/manifest` | Full manifest with presigned R2 download URLs |
| `POST` | `/tapes/:id/clips` | Request presigned upload URL for a clip |
| `POST` | `/tapes/:id/clips/:id/uploaded` | Confirm upload, create tracking records, send push |
| `POST` | `/tapes/:id/clips/:id/downloaded` | Confirm download, check if all participants have downloaded |
| `DELETE` | `/tapes/:id/clips/:id` | Delete clip and R2 assets |
| `GET` | `/share/:shareId` | Resolve share link to tape metadata |
| `POST` | `/sync/status` | Lightweight sync — returns pending download counts per tape |
| `POST` | `/tapes/:id/sync-push` | Owner-triggered push to all unsynced participants (rate limited: 1/24h) |
| `GET/POST/PUT/DELETE` | `/tapes/:id/collaborators/...` | Manage collaborators and invites |
| `PUT` | `/users/me/device-token` | Register APNs device token |
| `GET` | `/users/me` | Current user profile |

### Upload Flow

```
iOS → POST /tapes/:id/clips (metadata)
Server → returns presigned R2 upload URL
iOS → PUT to R2 (binary file)
iOS → PUT thumbnail to R2
iOS → POST /clips/:id/uploaded (confirms, triggers push)
```

### Download Flow

```
iOS → GET /share/:shareId (resolves tape)
iOS → GET /tapes/:id/manifest (full manifest with presigned download URLs)
iOS → downloads each clip from R2
iOS → saves to Photos library
iOS → POST /clips/:id/downloaded (fire-and-forget confirmation)
```

### D1 Database Tables

`users`, `tapes`, `collaborators`, `clips`, `clip_download_tracking`, `notification_preferences`, `sync_push_log`

### Cron Jobs

| Schedule | Job |
|----------|-----|
| Hourly | Expiry check — delete R2 assets past retention |
| Hourly | Sync warning — notify owner of clips near expiry with unsynced participants |
| Daily 03:00 UTC | Orphan cleanup — R2 assets with no DB record |
| Daily 04:00 UTC | Expired tape cleanup |
| Every 3 hours | Notification batch |

---

## 17. Authentication & Subscriptions

### Sign in with Apple

- `ASAuthorizationAppleIDCredential` → identity token sent to `POST /auth/apple`
- Server verifies against Apple's JWKS, creates/updates user, returns JWT (7-day lifetime)
- JWT stored in Keychain via `KeychainHelper`
- Credential state checked on launch; revoked → auto sign out

### Subscription Tiers

| Tier | Features |
|------|----------|
| **Free** | Up to 999 tapes (was 3, currently relaxed for testing), 3-day trial |
| **Plus** | Unlimited tapes, all features |
| **Together** | Everything in Plus, collaborative sharing |

- StoreKit 2 products: `com.tapes.plus.monthly/annual`, `com.tapes.together.monthly/annual`
- `EntitlementManager` resolves `AccessLevel` from active subscription
- `TrialManager` tracks 3-day trial from install date
- `PaywallView` shows tier comparison with monthly/annual billing toggle

---

## 18. Design System

### Tokens

- **Spacing:** 4, 8, 16, 24, 32, 48
- **Corner radius:** Cards 20, thumbnails 12, FAB 999 (pill)
- **FAB size:** 64pt
- **Colours:** Layered blues/grays (dark) and whites/grays (light); brand red `#E50914`; accent blue system blue
- **Typography:** System fonts mapped to SwiftUI semantic sizes
- **Timing:** Photo default 3s, max tape 45 min, max clips 100
- **Hit targets:** Minimum 44pt, recommended 48pt

### Components

| Component | Purpose |
|-----------|---------|
| `GlassAlertCard` | Frosted-glass alert card with icon, title, message, buttons. iOS 26+ uses `.glassEffect`; below uses ultra-thin material. |
| `SyncBadge` | Pill badge with count + direction arrow. Download (red), Upload (blue), Sync (rotating icon). Bouncing animation. |
| `VerticalVolumeSlider` | Collapsed circle that expands to vertical slider on tap. Auto-collapses after 3s. |
| `TapeCardView` | The central tape unit — title, carousel, FAB, action buttons, jiggle mode |
| `FabSwipableIcon` | Red circular FAB with horizontal swipe to cycle modes |
| `ClipCarousel` | Horizontal thumbnail strip with snap scrolling |

### Appearance

- System / Dark / Light via `@AppStorage("tapes_appearance_mode")`
- Applied as `preferredColorScheme` at the app root

---

## 19. Onboarding

Three-page tutorial with animated demonstrations:

1. **Camera Capture** — shows how to record video and take photos
2. **FAB Swipe** — demonstrates swiping between camera/gallery/transition modes
3. **Jiggle Reorder** — shows long-press to enter jiggle mode and drag clips between tapes

Can be replayed from Account → "Hot Tips".

---

## 20. Universal Links & Deep Links

- **Custom scheme:** `tapes://t/{shareId}`
- **Universal Links:** `https://api.tapes.app/t/{shareId}` (production) or `https://tapes-api.hi-7d5.workers.dev/t/{shareId}` (development)
- **Entitlements:** `applinks:tapes-api.hi-7d5.workers.dev`
- **Server:** Serves `/.well-known/apple-app-site-association` from the Worker
- **Handling:** `TapesApp` → `onOpenURL` / `onContinueUserActivity` → `NavigationCoordinator.handleShareLink`
- **Landing page:** Server renders a web page with app download prompt for users without the app

---

## 21. Backlog / Known Issues

### Confirmed Backlog Items

- **Notification batching:** When multiple clips are uploaded, each triggers a separate push notification. Planned fix: batch notifications with a 30-second delay window so recipients get one notification per upload session ("Jose added 8 clips to Barcelona").
- **Free tier tape limit:** Currently set to 999 (effectively unlimited) for testing. Needs to be restored to 3 for production.
- **`AsyncSemaphore`:** Referenced in docs/runbook but the file doesn't exist. Likely planned for bounded concurrency in batch imports.
- **Production APNS:** Entitlements show `aps-environment: development`. Production builds need `production`.
- **Associated domains:** Entitlements only list the Workers dev host. Production needs `applinks:api.tapes.app` for Universal Links.
- **`TapeSettingsSheet`:** An older/simpler settings sheet that is compiled but not wired into the current UI flow.
- **`CloudDownloadManager`:** Exists but has no references — superseded by `SharedTapeDownloadCoordinator`.
- **`getSharedTapes()` / `validateTape()`:** API methods implemented on both client and server but never called from the app UI.
- **Mubert credentials:** Customer ID and access token are hardcoded in `MubertAPIClient.swift` — credential exposure risk.
- **Two missing clips (tape 96BF122C):** The SyncChecker consistently reports 2 missing clips for this tape — likely legacy Live Photos uploaded with stripped metadata before the upload fix.

### Planned Future Features

- Per-clip transitions (beyond seam overrides)
- Filters and text overlays
- Real-time collaborative tape editing
- Cross-platform share targets
- Full Cast integration
