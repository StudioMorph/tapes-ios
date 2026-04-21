# Pending Tape Invites

## Summary

When a tape is shared with a user via email-protected link, a placeholder card appears in the relevant tab (Shared or Collab) so the user can discover and load the tape — even if they missed the push notification.

## Purpose & Scope

Previously, if a user missed the push notification for a shared tape and didn't receive the link manually, they had no way to discover it. This feature closes that gap with a push-driven invite system and a cold-start server fallback.

## Architecture

### Primary Path (Push-Driven)

1. Owner invites a user via `POST /tapes/:id/collaborators` (protected variant)
2. Server sends a push with `action: "tape_invite"` containing: `tape_id`, `tape_title`, `owner_name`, `share_id`, `mode`
3. `PushNotificationManager` receives the push (foreground or background) and persists a `PendingInvite` to `PendingInviteStore`
4. The Shared or Collab tab renders a `PendingInviteCard` at the top of its list
5. User taps **Load tape** → `resolveShare` + full download, invite removed
6. User taps **Dismiss** → confirmation dialog → `DELETE /invites/:tape_id/decline` + local removal

### Cold-Start Fallback

On app activation (`scenePhase == .active`), `MainTabView` calls `GET /tapes/shared` which now returns both `active` and `invited` collaborator rows. Any server-known tapes not in the local store or pending invites are injected as new `PendingInvite` entries.

## Key UI Components

- **`PendingInviteCard`**: Matches `TapeCardView` dimensions (same corner radius, background, shadow). Shows tape title, owner attribution, Dismiss (destructive) and Load tape (primary blue) buttons.
- **Dismiss Confirmation**: `GlassAlertCard` with destructive action. Warns the user this is irreversible.
- **Tab Badges**: Pending invite counts are included in the Shared/Collab tab badge numbers.

## Data Flow

```
Push Notification
    ↓
PushNotificationManager.handleInvitePush()
    ↓
PendingInviteStore.add(invite)  →  persisted to pending_invites.json
    ↓
SharedTapesView / CollabTapesView  (reads @EnvironmentObject pendingInviteStore)
    ↓
PendingInviteCard rendered
    ↓
User taps "Load tape"  →  resolveShare + download  →  invite removed
User taps "Dismiss"    →  confirmation  →  server decline + local removal
```

## Server Endpoints

- `DELETE /invites/:tape_id/decline` — marks collaborator as `declined`
- `GET /tapes/shared` — updated to include `invited` status, excludes `declined`, returns `share_id` and `status` per row

## Push Payload (tape_invite)

```json
{
  "aps": { "alert": { "title": "Tape Shared", "body": "Isabel shared \"Summer...\" with you" }, ... },
  "tape_id": "abc-123",
  "share_id": "xyz789",
  "tape_title": "Summer Holidays 2025 - Portugal",
  "owner_name": "Isabel",
  "mode": "view_only",
  "action": "tape_invite"
}
```

## Files Modified

### iOS
- `Tapes/Models/PendingInvite.swift` (new)
- `Tapes/Core/Persistence/PendingInviteStore.swift` (new)
- `Tapes/Views/Share/PendingInviteCard.swift` (new)
- `Tapes/Core/Notifications/PushNotificationManager.swift`
- `Tapes/Core/Networking/TapesAPIClient.swift`
- `Tapes/Models/SharedTapeItem.swift`
- `Tapes/Views/MainTabView.swift`
- `Tapes/Views/Share/SharedTapesView.swift`
- `Tapes/Views/Share/CollabTapesView.swift`

### Server
- `tapes-api/src/lib/apns.ts`
- `tapes-api/src/routes/collaborators.ts`
- `tapes-api/src/routes/tapes.ts`
- `tapes-api/src/routes/invites.ts` (new)
- `tapes-api/src/index.ts`

## Testing / QA Considerations

1. Share a protected tape with a user who has the app installed — verify push creates placeholder
2. Kill the app, re-open — verify cold-start fallback creates the placeholder
3. Tap "Load tape" — verify full download and placeholder removal
4. Tap "Dismiss" → confirm — verify server marks as declined and invite doesn't resurface
5. Verify tab badges include pending invite counts
6. Verify collaborative invites appear in Collab tab, view-only in Shared tab
