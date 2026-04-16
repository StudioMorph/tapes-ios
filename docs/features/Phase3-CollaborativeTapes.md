# Phase 3 — Collaborative Tapes

Enables multiple users to contribute clips to a shared tape, with role-based access control and real-time sync via push notifications.

## Purpose & Scope

Phase 3 extends the view-only sharing from Phase 2 to support collaborative tapes where invited participants can add their own clips. Owners and co-admins manage collaborators, while the system handles manifest synchronisation, clip downloads, and push notifications automatically.

## Key UI Components

### ShareLinkSection (embedded in `ShareModalView`)
- Inline sharing UI on the owner's side — replaces the old standalone `CollaboratorsView`.
- `Viewing tape` / `Collaborating tape` role tabs switch which of the 4 share variants is active.
- `Secured by email` toggle flips between open and protected variants for that role.
- "Authorised users" chip list is per-variant — revoking a chip only affects that variant.
- Invites are sent **one per tap**, scoped to the currently-selected `share_variant`.

### SharedTapeDetailView (Enhanced)
- **Contribute section** — PhotosPicker for adding clips to collaborative tapes
- **Upload progress** — per-clip progress with overall percentage
- **Admin section** — Sync Push button with rate-limit feedback
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
1. `TapesAPIClient.listCollaborators()` → display chips grouped by `share_variant` inside `ShareLinkSection`
2. `inviteCollaborator(email, shareVariant:)` → backend creates a record scoped to the variant, sends push to invitee
3. `revokeCollaborator(email, shareVariant:)` → backend sets status to `revoked` **for that variant only**; clip download tracking is expired only if the user has no remaining active variants on the tape

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
