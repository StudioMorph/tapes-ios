# Share Background Music with Tape — Implementation Plan

## Summary

When a tape is shared, the owner's selected background music travels with it: written once into the manifest, mp3 hosted on R2, downloaded to the receiver's device so local playback "just works." Music is write-once on the server (first share with music wins) and the receiver protects local choices on re-sync.

## The agreed rule

1. **Server is write-once for music.** First share that includes music attaches it. After that the music block on the server is frozen until tape deletion. No update endpoint, no overwrite path.
2. **Owner iOS** only uploads music when the server's music block is currently empty AND the owner has a local track. Detected via a flag on the existing `POST /tapes` response — no extra round trip.
3. **Receiver iOS** ignores the manifest's music block whenever the local tape already has a track (covers re-sync, owner adding music post-share, and local user customisation).

## Out of scope

- Owner being able to change music after first share (deferred — flag in `BACKLOG.md`).
- Exposing music to the export pipeline server-side. Export remains local-device-only and continues to mix the locally-stored mp3.
- Sharing track metadata for UI ("Now playing: Velvet Hum"). The cell display in the music sheet is local-state only and doesn't need to change.

---

## 1. Server (Cloudflare Worker)

### 1.1 New endpoints

Both authenticated, both owner-only (404 for non-owner; same error pattern as the rest of `tapes.ts`).

```
POST /tapes/:tapeId/music/prepare-upload
  → 200 { upload_url: string, public_url: string, expires_at: string }
  → 409 { error: { code: "MUSIC_ALREADY_SET" } }   ← server-side write-once backstop
  → 403 if caller is not the tape owner

POST /tapes/:tapeId/music/confirm
  body: { type: "library" | "prompt" | "mood",
          mood: string,                  ← raw value of tape.backgroundMusicMood
          prompt?: string,               ← only for type="prompt"
          public_url: string,            ← echo back for sanity check
          level?: number                 ← 0.0–1.0, defaults to 0.3 if omitted
        }
  → 200 { background_music: { type, mood, prompt?, url, level } }
  → 409 { error: { code: "MUSIC_ALREADY_SET" } }   ← idempotent backstop
  → 403 if caller is not the tape owner
```

The pair mirrors `prepare-upload` / `confirm-batch` for clips. R2 key convention: `music/<tape_id>.mp3`.

### 1.2 `POST /tapes` response — add `has_background_music`

`createTape` in `src/routes/tapes.ts` already returns the existing tape on idempotent calls. Add one field to both create and resolve branches:

```ts
return json({
  tape_id: ...,
  share_id: ..., /* etc */
  clips_uploaded: ...,
  has_background_music: hasMusicSet,    // ← new
}, status);
```

`hasMusicSet` is `tape.tape_settings` parsed → `background_music` present and non-null. This is the iOS "should I upload music?" signal in one cheap field — no extra GET.

### 1.3 Manifest endpoint signs the music URL

`src/routes/manifest.ts` currently parses `tape_settings` and returns it verbatim. Add: if `tape_settings.background_music?.url` is set, replace it with a presigned download URL the same way clip URLs are signed.

```ts
if (tapeSettings.background_music?.url) {
  const key = extractR2Key(tapeSettings.background_music.url);
  tapeSettings.background_music.url = await generatePresignedDownloadUrl({ ...r2Opts, key });
}
```

### 1.4 R2 cleanup cron

`src/routes/scheduled.ts` → `runSharedAssetCleanup`. Per expiring tape, also try `env.MEDIA.delete('music/<tape_id>.mp3')` (best-effort, alongside clip deletions). Don't read tape_settings — just attempt the deterministic key.

### 1.5 No D1 migration needed

`tape_settings` is a JSON column already. The `background_music` block sits inside it.

### 1.6 New routes wired in `src/index.ts`

Two regex entries beneath the existing `/tapes/:id/...` routes.

---

## 2. iOS — owner upload path

### 2.1 `Tapes/Core/Networking/TapesAPIClient.swift`

- Extend `CreateTapeResponse` with `hasBackgroundMusic: Bool?` (decode from `has_background_music`).
- New struct `BackgroundMusicUpload`:
  ```swift
  struct BackgroundMusicUpload: Decodable {
    let uploadUrl: String
    let publicUrl: String
    let expiresAt: String
  }
  ```
- New methods:
  ```swift
  func prepareBackgroundMusicUpload(tapeId: String) async throws -> BackgroundMusicUpload
  func confirmBackgroundMusic(tapeId: String,
                              type: String,
                              mood: String,
                              prompt: String?,
                              publicUrl: String,
                              level: Double) async throws
  ```
- Both throw a typed error mapped from `409 MUSIC_ALREADY_SET` so the upload coordinator can swallow it as "fine, server got there first."

### 2.2 `Tapes/Core/Networking/ShareUploadCoordinator.swift`

After `ensureTapeUploaded`'s create call returns successfully, before clip uploads start, insert a single-step guarded music upload:

```swift
if response.hasBackgroundMusic == false,
   tape.hasBackgroundMusic,
   let mp3 = MubertAPIClient.shared.cachedTrackURL(for: tape.id) {
    try await uploadBackgroundMusicIfNeeded(tape: tape, mp3: mp3, api: api)
}
```

`uploadBackgroundMusicIfNeeded`:
1. Call `prepareBackgroundMusicUpload(tapeId:)`.
2. PUT the mp3 bytes to `upload_url` (same `URLSession.shared.uploadTask` shape as clip uploads).
3. Call `confirmBackgroundMusic(...)` with `type` derived from `tape.backgroundMusicPrompt` (prompt) or default (library/mood — single field for now, treat all non-prompt as `library`).
4. On `MUSIC_ALREADY_SET` — log, treat as success.
5. Failure path: log + continue. Music is best-effort. We never fail the share over music.

Owner-only check is implicit on the server (`403`). iOS doesn't need to know who the owner is — `403` means skip silently.

No change to `tape_settings` payload of `POST /tapes` (music stays in the new endpoints).

### 2.3 `Tapes/Models/Tape.swift`

No model changes. `backgroundMusicMood` / `backgroundMusicPrompt` / `backgroundMusicVolume` are already there.

---

## 3. iOS — receiver download path

### 3.1 `Tapes/Core/Networking/TapeManifest.swift`

Already has `ManifestBackgroundMusic { type, mood, url, level }`. Add `prompt: String?`:

```swift
struct ManifestBackgroundMusic: Codable {
    let type: String?
    let mood: String?
    let prompt: String?
    let url: String?
    let level: Double?
}
```

### 3.2 `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift`

In `buildTape(from manifest:...)` (around line 660), after constructing the base tape, layer in the music block guarded:

```swift
let bg = manifest.tapeSettings.backgroundMusic
if let bg, !tape.hasBackgroundMusic {
    tape.backgroundMusicMood = bg.mood
    tape.backgroundMusicPrompt = bg.prompt
    if let level = bg.level { tape.backgroundMusicVolume = level }
}
```

For the **first-time download path** (the `existingTape == nil` branch around line 232–248), kick off a background mp3 download after the tape is added to the store. The mp3 lands at `MubertAPIClient.trackStorageDir()/<tape.id.uuidString>.mp3` — the local key the player already uses.

For the **returning sync path** (`existingTape != nil`, line 225–230), do nothing music-related. The receiver guard already protected the local tape.

### 3.3 New helper in `MubertAPIClient`

```swift
/// Downloads a shared-tape music file from a signed R2 URL into the durable
/// per-tape slot, so existing playback finds it via cachedTrackURL(for:).
func downloadSharedMusic(from remoteURL: URL, tapeID: UUID) async throws
```

Reuses `ensureTrackStorageDir()` + the same write pattern as `downloadTrack`. Skip if file already present.

---

## 4. Storage strategy

| Concern | Decision |
| --- | --- |
| R2 key | `music/<tape_id>.mp3` |
| iOS local key (sender + receiver) | `Application Support/mubert_tracks/<tape_uuid>.mp3` (already in place) |
| File protection | Inherits Application Support's default; matches existing |
| iCloud backup | Excluded (already done in `ensureTrackStorageDir`) |
| Manifest URL | Presigned download URL, 1-hour expiry, generated per-fetch (same as clips) |
| Lifetime | Tied to tape's `shared_assets_expire_at` — purged by `runSharedAssetCleanup` |

---

## 5. Backwards compatibility

- **Existing shared tapes with music**: owner's local tape has `backgroundMusicMood` set, server's `tape_settings.background_music` is `null` (because no upload has ever happened). On the **next** share (whether collab contribution or view re-share), the owner's app sees `has_background_music: false` from the create response, sees the local track, and uploads. Music attaches.
- **Existing shared tapes without music**: nothing changes. Owner can pick music later → next share carries it.
- **Receivers on old iOS builds (n/a yet)**: the new manifest field `background_music` is already in the schema; old clients ignore it. Forward compatible.
- **Old server, new iOS**: iOS calls `prepare-upload` → 404 → typed error → log + skip. Share still succeeds. Acceptable transitional state during deploy.

Mitigation for the brief window where iOS is rolled out but Worker isn't: deploy Worker first.

---

## 6. Risks

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Mubert licensing forbids redistributing 12K Library tracks | Medium | Re-read Mubert agreement before rollout. If forbidden, add a `type == "library"` skip on the iOS owner side and document it. AI/prompt tracks are generated content — should be safe. |
| Manifest URL signing breaks existing shared tapes | Low | The new code path only fires when `background_music?.url` is set, which is currently always `null` on production tapes. Safe to ship before the first owner uploads music. |
| R2 PUT fails mid-flight, leaves orphan | Low | Confirm endpoint only writes the music block on success. Orphan mp3 in R2 gets cleaned by `runSharedAssetCleanup` when the tape eventually expires. Acceptable. |
| Receiver re-sync downloads music repeatedly | Low | `downloadSharedMusic` skips if file already present. Plus the build-tape guard prevents re-touching `backgroundMusicMood` once set. |
| Owner removes music locally then re-shares — server still serves the old track to new receivers | Known, by design | Acceptable per agreed rule. Owner cannot mutate music post-attach. Backlog if this becomes a real complaint. |

---

## 7. Deploy steps

1. **Worker** (`tapes-api` repo, on `main`):
   - Add `prepare-upload` + `confirm` handlers in new `src/routes/music-share.ts` (kept separate from Mubert proxy `music.ts`).
   - Wire two regex routes in `src/index.ts`.
   - Extend `CreateTapeResponse` shape in `tapes.ts` (both branches).
   - Update `manifest.ts` to sign `background_music.url`.
   - Update `scheduled.ts` `runSharedAssetCleanup`.
   - `npx wrangler deploy` → live worker at `tapes-api.hi-7d5.workers.dev`.
   - Smoke: `curl` the manifest of an existing shared tape, verify `tape_settings.background_music` is unchanged (still `null`).
2. **iOS** (`tapes-ios` repo, on `main`):
   - Implement §2 + §3.
   - Update `docs/features/BackgroundMusic.md` to document the share/sync behaviour.
   - Build to Jose's phone and Isabel's phone.
3. **Verify** (see §8). If green, commit + push.

Worker first because iOS gracefully degrades (logs + skips) if endpoints are missing, but the reverse — Worker live with no iOS callers — is harmless.

---

## 8. Verification checklist (on-device)

Run on Jose's phone unless noted. Pre-condition: both phones logged in, network up, paywall in dev mode.

1. **First share with music — view-only**
   - Create new tape, add 2 clips, pick a Library track, share via Copy Link.
   - On Isabel's phone, open the link.
   - **Expect:** tape downloads, music wave shows the track, playback has the track.

2. **First share with music — collab**
   - Create new collab tape, add 2 clips, pick a Prompt track, share via Copy Link.
   - On Isabel's phone, open the link.
   - **Expect:** music wave shows the prompt-track name, playback has the track.

3. **Subsequent contribution doesn't change music**
   - On Jose's phone, change the music to a different track on the collab tape from #2.
   - Add a new clip → it uploads as a contribution.
   - On Isabel's phone, sync.
   - **Expect:** Isabel's tape still has the *original* prompt track. Jose's local tape still has his new track. No reversion on Jose's side.

4. **Receiver customisation survives re-sync**
   - Isabel changes the music on her local copy of the shared tape from #1.
   - Jose adds another clip to that tape (if applicable) → triggers a sync push.
   - Isabel re-opens and syncs.
   - **Expect:** Isabel's chosen track is still there; not reverted to Jose's original.

5. **Tape that started without music can still attach music later**
   - Create a new tape, share *without* music to Isabel.
   - On Jose's phone, pick a track on that same tape, share again.
   - Isabel re-syncs (or accepts the next contribution push).
   - **Expect:** Isabel's tape now has the music Jose picked.

6. **Tape that started with music doesn't change after**
   - Tape from #1, on Jose's phone, change to a different Library track.
   - Add a clip to bump the share.
   - Isabel re-syncs.
   - **Expect:** Isabel's tape music is unchanged (the original from #1).

7. **R2 cleanup**
   - Manually expire a test tape via `wrangler d1 execute` (`UPDATE tapes SET shared_assets_expire_at = '2020-01-01T00:00:00Z' WHERE tape_id = ...`).
   - Trigger the daily cron: `npx wrangler dev --test-scheduled` and curl the scheduled hook (or wait the day).
   - **Expect:** `music/<tape_id>.mp3` is no longer in R2.

8. **Build still green** — `xcodebuild` clean build, no new lint warnings.

---

## 9. Open questions

1. **Mubert library track redistribution licensing** — needs a quick read of the Mubert ToS before turning on `type == "library"` upload. If unclear, ship with library uploads disabled and only upload AI/prompt tracks; library shares will continue to be local-only on the owner's device. Decide before §2.2 ships.
2. **Music file size cap** — 30s mp3s are ~1–2 MB. Worth enforcing a server-side size cap on the presigned PUT (e.g. 5 MB) to avoid abuse. Easy add.

---

## 10. File touch summary

**`tapes-api`**
- `src/routes/tapes.ts` — extend `CreateTapeResponse` with `has_background_music`.
- `src/routes/manifest.ts` — sign `background_music.url`.
- `src/routes/music-share.ts` — new file, two handlers.
- `src/routes/scheduled.ts` — extend `runSharedAssetCleanup`.
- `src/index.ts` — wire two new routes.

**`tapes-ios`**
- `Tapes/Core/Networking/TapesAPIClient.swift` — new methods + `CreateTapeResponse.hasBackgroundMusic`.
- `Tapes/Core/Networking/TapeManifest.swift` — add `prompt` to `ManifestBackgroundMusic`.
- `Tapes/Core/Networking/ShareUploadCoordinator.swift` — guarded music upload after tape create.
- `Tapes/Core/Music/MubertAPIClient.swift` — `downloadSharedMusic(from:tapeID:)`.
- `Tapes/Features/Import/SharedTapeDownloadCoordinator.swift` — apply music block on first build, fire mp3 download.
- `docs/features/BackgroundMusic.md` — document share/sync behaviour.
- `docs/BACKLOG.md` — add "owner can update music after first share" deferred item.
