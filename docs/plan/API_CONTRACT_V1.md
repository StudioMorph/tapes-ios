# Tapes API Contract v1

Base URL: `https://api.tapes.app` (production) / `https://api-dev.tapes.app` (dev)

All requests and responses use `application/json` unless noted.
All timestamps are ISO 8601 UTC.
All IDs are UUIDs.

---

## Authentication

### Strategy

1. iOS app performs Sign in with Apple, receives `identityToken` (JWT signed by Apple)
2. iOS sends `identityToken` to `POST /auth/apple`
3. Server verifies token against Apple's JWKS (`https://appleid.apple.com/auth/keys`)
4. Server creates or updates user record in D1
5. Server returns a short-lived access token (JWT, 7 days) signed with a server secret
6. iOS stores token in Keychain, sends it as `Authorization: Bearer <token>` on all subsequent requests
7. On 401, iOS re-authenticates with Apple and calls `POST /auth/apple` again

### Token Claims

```json
{
  "sub": "user_uuid",
  "email": "user@example.com",
  "iat": 1712000000,
  "exp": 1712604800
}
```

---

## Endpoints

### Auth

#### `POST /auth/apple`

Exchange Apple identity token for a Tapes access token.

**Request:**
```json
{
  "identity_token": "eyJhbGciOiJSUzI1NiIs...",
  "full_name": "Jose Garcia",
  "email": "jose@email.com"
}
```

`full_name` and `email` are optional — Apple only provides them on first sign-in.

**Response: `200 OK`**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "user_id": "uuid",
    "email": "jose@email.com",
    "name": "Jose Garcia",
    "tier": "plus",
    "created_at": "2026-04-12T09:00:00Z"
  }
}
```

---

### Tapes

#### `POST /tapes`

Create a master tape record for sharing. Called when the owner initiates a share.

**Request:**
```json
{
  "tape_id": "uuid",
  "title": "Barcelona Summer",
  "mode": "collaborative",
  "expires_at": null,
  "tape_settings": {
    "default_audio_level": 1.0,
    "transition": {
      "type": "crossfade",
      "duration_ms": 1100
    },
    "background_music": {
      "mood": "dreamy",
      "level": 0.3
    },
    "merge_settings": {
      "orientation": "auto",
      "background_blur": true
    }
  }
}
```

**Response: `201 Created`**
```json
{
  "tape_id": "uuid",
  "share_id": "short_alphanum_8char",
  "share_url": "https://tapes.app/t/short_alphanum_8char",
  "deep_link": "tapes://t/short_alphanum_8char",
  "created_at": "2026-04-12T09:00:00Z"
}
```

`share_id` is a short, URL-safe alphanumeric string for sharing links.

---

#### `GET /tapes/:tape_id`

Get tape metadata (owner or collaborator only).

**Response: `200 OK`**
```json
{
  "tape_id": "uuid",
  "title": "Barcelona Summer",
  "mode": "collaborative",
  "owner_id": "uuid",
  "owner_name": "Jose Garcia",
  "share_id": "short_alphanum",
  "expires_at": null,
  "created_at": "2026-04-12T09:00:00Z",
  "updated_at": "2026-04-12T12:00:00Z",
  "clip_count": 5,
  "collaborator_count": 3
}
```

---

#### `DELETE /tapes/:tape_id`

Delete a tape. Owner only. Immediately purges all R2 assets.

**Response: `204 No Content`**

---

### Clips

#### `POST /tapes/:tape_id/clips`

Request a presigned upload URL for a new clip.

**Request:**
```json
{
  "clip_id": "uuid",
  "type": "video",
  "duration_ms": 8400,
  "trim_start_ms": 0,
  "trim_end_ms": 8400,
  "audio_level": 1.0,
  "recorded_at": "2026-04-12T09:00:00Z",
  "file_size_bytes": 12456789,
  "content_type": "video/mp4",
  "ken_burns_params": null,
  "live_photo_as_video": null,
  "live_photo_sound": null
}
```

**Response: `201 Created`**
```json
{
  "clip_id": "uuid",
  "upload_url": "https://tapes-media.r2.cloudflarestorage.com/clips/uuid.mp4?X-Amz-...",
  "upload_url_expires_at": "2026-04-12T10:00:00Z",
  "thumbnail_upload_url": "https://tapes-media.r2.cloudflarestorage.com/thumbs/uuid.jpg?X-Amz-...",
  "order_index": 6
}
```

The iOS client then uploads directly to R2 using the presigned URL via `PUT`.

---

#### `POST /tapes/:tape_id/upload-batch`

Declares an upload batch before clips are uploaded. The server records the expected clip count and holds notifications until the batch completes (all clips confirmed via `/uploaded`). Only one active batch per tape per user at a time.

**Request:**
```json
{
  "clip_count": 5,
  "batch_type": "invite",
  "mode": "view_only"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `clip_count` | `int` | Number of clips that will be uploaded in this batch |
| `batch_type` | `string` | `"invite"` (initial share) or `"update"` (adding clips to existing share) |
| `mode` | `string` | `"view_only"` or `"collaborative"` |

**Response: `201 Created`**
```json
{
  "batch_id": "uuid",
  "expected_count": 5
}
```

---

#### `POST /tapes/:tape_id/clips/:clip_id/uploaded`

Called by iOS after a successful upload to R2. Finalises the clip record, creates download tracking records for all participants. If an upload batch is active, increments the batch counter. When the counter reaches the expected count, the server sends a single consolidated push notification to all other participants.

**Request:**
```json
{
  "cloud_url": "https://tapes-media.r2.cloudflarestorage.com/clips/uuid.mp4",
  "thumbnail_url": "https://tapes-media.r2.cloudflarestorage.com/thumbs/uuid.jpg"
}
```

**Response: `200 OK`**
```json
{
  "clip_id": "uuid",
  "order_index": 6,
  "expires_at": "2026-04-19T09:00:00Z",
  "tracking_records_created": 3,
  "batch_completed": true
}
```

`batch_completed` is `true` when this confirmation completed the active batch and notifications were sent. `false` or absent otherwise.

---

#### `POST /tapes/:tape_id/clips/:clip_id/downloaded`

Called by iOS when a clip has been fully downloaded by the current user.

**Response: `200 OK`**
```json
{
  "clip_id": "uuid",
  "all_downloaded": true,
  "asset_deleted": true
}
```

If `all_downloaded` is true, the R2 asset was deleted immediately.

---

### Manifest

#### `GET /tapes/:tape_id/manifest`

Returns the complete `.tape` JSON manifest for rebuilding the tape on a recipient's device.

**Response: `200 OK`**

Returns the full `.tape` JSON as defined in the spec (Section 1).

---

### Collaborators

#### `POST /tapes/:tape_id/collaborators`

Invite a collaborator. Owner or co-admin only. Requires Plus or Together tier.

**Request:**
```json
{
  "email": "anna@email.com",
  "role": "collaborator"
}
```

**Response: `201 Created`**
```json
{
  "tape_id": "uuid",
  "user_id": "uuid or null",
  "email": "anna@email.com",
  "role": "collaborator",
  "status": "invited",
  "invited_by": "uuid"
}
```

---

#### `GET /tapes/:tape_id/collaborators`

List all collaborators on a tape. Owner or collaborator.

**Response: `200 OK`**
```json
{
  "collaborators": [
    {
      "user_id": "uuid",
      "email": "anna@email.com",
      "name": "Anna",
      "role": "collaborator",
      "status": "active",
      "joined_at": "2026-04-12T10:00:00Z"
    }
  ]
}
```

---

#### `PUT /tapes/:tape_id/collaborators/:user_id/role`

Change a collaborator's role. Owner only.

**Request:**
```json
{
  "role": "co-admin"
}
```

**Response: `200 OK`**

---

#### `DELETE /tapes/:tape_id/collaborators/:user_id`

Revoke a collaborator's access. Owner or co-admin only.

**Response: `204 No Content`**

---

### Share Resolution

#### `GET /share/:share_id`

Resolve a share link or deep link. Called when a recipient taps a link or opens a `.tape` file. Validates identity, checks permissions, returns tape metadata for building on device.

**Response: `200 OK`**
```json
{
  "tape_id": "uuid",
  "title": "Barcelona Summer",
  "mode": "view_only",
  "owner_name": "Jose Garcia",
  "clip_count": 5,
  "status": "active",
  "user_role": "collaborator",
  "manifest_url": "/tapes/{tape_id}/manifest"
}
```

**Response: `403 Forbidden`** — user not on collaborator list for non-view-only tapes.

**Response: `410 Gone`** — tape expired or deleted.

---

### Sync

#### `POST /sync/status`

Lightweight sync check. Returns pending download counts for the authenticated user's tapes. One request replaces per-tape manifest polling.

**Request:**
```json
{
  "tape_ids": ["uuid1", "uuid2"]
}
```

`tape_ids` is optional. If omitted, returns all tapes with pending downloads for the user.

**Response: `200 OK`**
```json
{
  "tapes": {
    "uuid1": 3,
    "uuid2": 1
  }
}
```

Only tapes with pending downloads (`> 0`) are included. Empty object `{}` means nothing to download.

---

---

### Device Token

#### `PUT /users/me/device-token`

Register or update APNs device token for push notifications.

**Request:**
```json
{
  "device_token": "hex_encoded_apns_token",
  "platform": "ios"
}
```

**Response: `204 No Content`**

---

### Notification Preference

#### `PUT /users/me/notification-preference`

Set the user's notification delivery mode and timezone.

**Request:**
```json
{
  "delivery_mode": "hourly",
  "timezone": "Europe/London"
}
```

Valid `delivery_mode` values: `auto`, `hourly`, `twice_daily`, `once_daily`.

**Response: `200 OK`**
```json
{
  "delivery_mode": "hourly",
  "timezone": "Europe/London"
}
```

---

### User

#### `GET /users/me`

Get current user profile.

**Response: `200 OK`**
```json
{
  "user_id": "uuid",
  "email": "jose@email.com",
  "name": "Jose Garcia",
  "tier": "plus",
  "email_verified": true,
  "delivery_mode": "auto",
  "timezone": "Europe/London",
  "created_at": "2026-04-12T09:00:00Z"
}
```

---

## Error Format

All errors return:

```json
{
  "error": {
    "code": "TAPE_NOT_FOUND",
    "message": "The requested tape does not exist or has been deleted."
  }
}
```

### Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| `UNAUTHORIZED` | 401 | Missing or invalid token |
| `FORBIDDEN` | 403 | Valid token but insufficient permissions |
| `TAPE_NOT_FOUND` | 404 | Tape doesn't exist or is deleted |
| `CLIP_NOT_FOUND` | 404 | Clip doesn't exist |
| `TAPE_EXPIRED` | 410 | Tape has expired |
| `TIER_REQUIRED` | 403 | Feature requires Plus or Together tier |
| `RATE_LIMITED` | 429 | Too many requests |
| `UPLOAD_TOO_LARGE` | 413 | File exceeds size limit |
| `VALIDATION_ERROR` | 422 | Invalid request body |
| `INTERNAL_ERROR` | 500 | Server error |

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `POST /auth/apple` | 10/min per IP |
| `POST /tapes/:id/clips` | 30/min per user |
| All other endpoints | 60/min per user |

---

## R2 Upload Flow

```
iOS                          Workers API                    R2
 |                               |                          |
 |  POST /tapes/:id/upload-batch |                          |
 |  { clip_count, batch_type,    |                          |
 |    mode }                     |                          |
 |------------------------------>|                          |
 |  { batch_id }                |  Create batch record     |
 |<------------------------------|  (expected_count=N)      |
 |                               |                          |
 |  — repeat for each clip —     |                          |
 |                               |                          |
 |  POST /tapes/:id/clips       |                          |
 |  (clip metadata)              |                          |
 |------------------------------>|                          |
 |                               |  Generate presigned URL  |
 |                               |------------------------->|
 |  { upload_url, thumb_url }   |                          |
 |<------------------------------|                          |
 |                               |                          |
 |  PUT upload_url               |                          |
 |  (binary file body)           |                          |
 |------------------------------------------------------>  |
 |                               |                          |
 |  PUT thumbnail_upload_url     |                          |
 |  (binary thumbnail)           |                          |
 |------------------------------------------------------>  |
 |                               |                          |
 |  POST /clips/:id/uploaded    |                          |
 |  (confirm URLs)               |                          |
 |------------------------------>|                          |
 |                               |  Create tracking records |
 |                               |  Increment batch counter |
 |                               |  If counter == N:        |
 |                               |    Send ONE push to all  |
 |                               |    participants          |
 |  { order_index, expires_at,  |                          |
 |    batch_completed }          |                          |
 |<------------------------------|                          |
```

### Batch Notification Payloads

The server constructs the push notification based on `batch_type` and `mode`:

**Initial share (invite) — view-only:**
```json
{
  "aps": {
    "alert": { "title": "Tape invite", "body": "Jose invited you to see and follow their \"Holidays in Portugal\" Tape" },
    "sound": "default", "badge": 1, "content-available": 1, "category": "TAPE_INVITE"
  },
  "tape_id": "uuid", "share_id": "short_id", "action": "tape_invite",
  "tape_title": "Holidays in Portugal", "owner_name": "Jose", "mode": "view_only"
}
```

**Initial share (invite) — collaborative:**
```json
{
  "aps": {
    "alert": { "title": "Tape invite", "body": "Jose invited you to collaborate on \"Holidays in Portugal\" Tape" },
    "sound": "default", "badge": 1, "content-available": 1, "category": "TAPE_INVITE"
  },
  "tape_id": "uuid", "share_id": "short_id", "action": "tape_invite",
  "tape_title": "Holidays in Portugal", "owner_name": "Jose", "mode": "collaborative"
}
```

**Update (contribution) — view-only:**
```json
{
  "aps": {
    "alert": { "title": "Tape Update - Holidays in Portugal", "body": "Jose added 5 new clips to this tape" },
    "sound": "default", "badge": 1, "content-available": 1, "category": "TAPE_SHARE"
  },
  "tape_id": "uuid", "share_id": "short_id", "action": "sync_update",
  "clip_count": 5
}
```

**Update (contribution) — collaborative:**
```json
{
  "aps": {
    "alert": { "title": "Tape Update - Holidays in Portugal", "body": "Jose contributed 5 new clips to this tape" },
    "sound": "default", "badge": 1, "content-available": 1, "category": "TAPE_SHARE"
  },
  "tape_id": "uuid", "share_id": "short_id", "action": "sync_update",
  "clip_count": 5
}
```

For singular clips, body reads "a new clip" instead of "N new clips".

---

## Invites

### `DELETE /invites/:tape_id/decline`

Marks the current user's collaborator row as `declined` for the given tape. The invite will not resurface in `GET /tapes/shared` or via push notifications.

**Response:** `204 No Content`

**Error:** `404` if no pending invite exists.

---

## `GET /tapes/shared` (Updated)

Now returns both `active` and `invited` collaborator rows (excludes `declined` and `revoked`). Each row includes:

| Field | Type | Description |
|-------|------|-------------|
| `share_id` | `string` | The share ID for the variant the user was invited to |
| `status` | `string` | `active` or `invited` |

---

## Scheduled Jobs (Cron Triggers)

| Job | Cron | Handler |
|-----|------|---------|
| Expiry check | `0 * * * *` (hourly) | Delete R2 assets where `expires_at` has passed |
| Sync warning | `0 * * * *` (hourly) | Notify owner when clips within 48h of expiry have unsynced collaborators |
| Orphan cleanup | `0 3 * * *` (daily 03:00 UTC) | Delete R2 assets with no DB record older than 24h |
| Expired tape cleanup | `0 4 * * *` (daily 04:00 UTC) | Mark expired view-only tapes, flag for removal |
| Stale batch cleanup | `0 * * * *` (hourly) | Delete upload batch records older than 1h that never completed |
