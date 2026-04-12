# Phase 3 — Collaborative Tapes

Enables multiple users to contribute clips to a shared tape, with role-based access control and real-time sync via push notifications.

## Purpose & Scope

Phase 3 extends the view-only sharing from Phase 2 to support collaborative tapes where invited participants can add their own clips. Owners and co-admins manage collaborators, while the system handles manifest synchronisation, clip downloads, and push notifications automatically.

## Key UI Components

### CollaboratorsView
- Full-screen modal presented from `SharedTapeDetailView`
- Invite section with email input and role picker (Collaborator / Co-Admin)
- Member list with contextual menu (promote, demote, revoke) — owner only
- Role badges with colour coding (Owner: orange, Co-Admin: blue, Collaborator: grey)
- Destructive action confirmation alert for revocation

### SharedTapeDetailView (Enhanced)
- **Contribute section** — PhotosPicker for adding clips to collaborative tapes
- **Upload progress** — per-clip progress with overall percentage
- **Admin section** — Sync Push button with rate-limit feedback
- **Collaborator toolbar** — person.2 icon in navigation bar opens CollaboratorsView
- **Pull-to-refresh** — fetches latest manifest and downloads new clips incrementally
- **Contributor attribution** — clip rows show contributor name

## Data Flow

### Contribution Upload
1. User taps "Add Clips" → `PhotosPicker` opens
2. Selected items load via `loadTransferable(type: Data.self)`
3. Each item queued via `CloudUploadManager.upload()`
4. Upload pipeline: `createClip` → R2 presigned PUT → `confirmUpload`
5. Backend notifies other participants via APNs on upload confirm
6. After uploads complete, local manifest refreshed

### Manifest Sync
1. Push notification or pull-to-refresh triggers `refreshManifest()`
2. API returns latest manifest with all clips
3. `CloudDownloadManager.downloadNewClips()` compares existing IDs
4. Only new clips are downloaded (incremental)

### Collaborator Management
1. `TapesAPIClient.listCollaborators()` → display in CollaboratorsView
2. `inviteCollaborator()` → backend creates record, sends push to invitee
3. `updateRole()` → backend validates owner permission, updates role
4. `revokeCollaborator()` → backend sets status to revoked, expires tracking

## Backend Changes

- `syncPush` now sends actual push notifications to unsynced participants
- `confirmUpload` now notifies all tape participants when a new clip is added
- Manifest endpoint joins `contributor_name` from users table per clip
- All role-based actions validated server-side against user tier and collaborator role

## Design Tokens Used

- `Tokens.Spacing` — all padding and gaps
- `Tokens.Colors` — primaryBackground, secondaryBackground, primaryText, secondaryText, tertiaryText, systemBlue, systemRed
- `Tokens.Radius` — card, thumb for rounded rectangles
- `Tokens.Typography` — caption, headline, body

## Testing / QA Considerations

- Verify role-based UI: only owner sees manage menu and admin controls
- Verify contributors cannot see admin section
- Verify Sync Push shows rate-limit error after second tap within 24h
- Verify pull-to-refresh downloads only new clips (not re-downloading existing)
- Verify revoked collaborator loses access on next manifest fetch
- Test upload failure + retry from SharedTapeDetailView
