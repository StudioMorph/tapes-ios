# Phase 2 — View-Only Sharing

## Summary

Complete view-only sharing flow: share a tape via link, recipients receive push notification, open the app, validate permissions, download clips, and play back — with clips becoming playable as they download.

## Architecture

### Sharing Side (Owner)
```
Tap share icon → ShareModalView → ShareFlowView
  → POST /tapes (create server record)
  → POST /tapes/:id/collaborators (invite by email)
  → Server sends APNs push to invited user
  → Share link displayed: tapes://t/{shareId}
  → UIActivityViewController for link distribution
```

### Recipient Side
```
Tap link / push notification
  → NavigationCoordinator.handleShareLink
  → GET /share/{shareId} (resolveShare — auto-adds viewer)
  → Switch to Shared tab, open SharedTapeDetailView
  → GET /tapes/:id/validate (check permissions, expiry)
  → GET /tapes/:id/manifest (full .tape JSON)
  → CloudDownloadManager downloads clips in parallel
  → Play button appears after first clip completes
  → SharedTapeBuilder converts manifest → local Tape model
  → TapePlayerView plays the tape
  → POST /tapes/:id/clips/:clipId/downloaded (per clip)
  → Server deletes R2 assets when all participants download
```

## Key Components

### Backend (tapes-api)
| Component | File | Purpose |
|-----------|------|---------|
| Validate | `routes/tapes.ts` | `GET /tapes/:id/validate` — permission + expiry check |
| Shared list | `routes/tapes.ts` | `GET /tapes/shared` — user's shared tapes |
| APNs | `lib/apns.ts` | Send push notifications via Apple APNs |
| Invite push | `routes/collaborators.ts` | Sends push on invite with tape title |

### iOS (tapes-ios)
| Component | File | Purpose |
|-----------|------|---------|
| CloudDownloadManager | `Core/Networking/CloudDownloadManager.swift` | Parallel downloads, retry, caching |
| SharedTapeBuilder | `Core/Networking/SharedTapeBuilder.swift` | Manifest → Tape model conversion |
| NavigationCoordinator | `Core/Navigation/NavigationCoordinator.swift` | Deep link → tab switch → tape open |
| PushNotificationManager | `Core/Notifications/PushNotificationManager.swift` | Push registration, handling, routing |
| AppDelegate | `AppDelegate.swift` | Device token callbacks |
| SharedTapeDetailView | `Views/Share/SharedTapeDetailView.swift` | Validate, download, play UI |
| SharedTapesView | `Views/Share/SharedTapesView.swift` | Shared tab with filter + navigation |

## Download Flow

1. `CloudDownloadManager.downloadTape()` creates parallel download tasks
2. Each clip downloads via `URLSession.download(for:)` to a temp file
3. File moves to `Caches/shared_tapes/{tapeId}/{clipId}.{ext}`
4. Thumbnail downloaded separately to `{clipId}_thumb.jpg`
5. Server notified via `POST /clips/:id/downloaded`
6. When all participants download a clip, server deletes R2 asset
7. Retry with exponential backoff (max 3 attempts)

## Streaming Playback

- Play button appears as soon as **any** clip finishes downloading
- `SharedTapeBuilder` only includes clips with completed local files
- User can play available clips while remaining clips download
- Full tape becomes playable when all clips complete

## Push Notifications

- Categories: `TAPE_SHARE`, `TAPE_INVITE`
- Actions: `VIEW_TAPE` (foreground)
- Foreground: displayed as banner
- Tap: routes through `NavigationCoordinator` via `share_id`
- Device token registered with API via `PUT /users/me/device-token`

## Testing / QA Considerations

- Share link works for authenticated users
- View-only auto-adds recipient as viewer
- Collaborative requires prior invite
- Expired tapes return 410
- Revoked collaborators return 403
- Downloads resume from cache on re-open
- Push notification navigates to correct tape
- R2 cleanup fires when all download confirmations received
