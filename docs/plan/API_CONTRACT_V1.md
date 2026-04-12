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

#### `POST /tapes/:tape_id/clips/:clip_id/uploaded`

Called by iOS after a successful upload to R2. Finalises the clip record, creates download tracking records for all participants, and triggers notifications.

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
  "tracking_records_created": 3
}
```

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

#### `POST /tapes/:tape_id/sync-push`

Owner triggers a Sync Push. Sends push notification to all collaborators who haven't fully downloaded. Max once per 24 hours per tape.

**Response: `200 OK`**
```json
{
  "notified_count": 2,
  "next_available_at": "2026-04-13T09:00:00Z"
}
```

**Response: `429 Too Many Requests`** — already pushed within 24 hours.

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
| `RATE_LIMITED` | 429 | Too many requests (e.g. Sync Push cooldown) |
| `UPLOAD_TOO_LARGE` | 413 | File exceeds size limit |
| `VALIDATION_ERROR` | 422 | Invalid request body |
| `INTERNAL_ERROR` | 500 | Server error |

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `POST /auth/apple` | 10/min per IP |
| `POST /tapes/:id/clips` | 30/min per user |
| `POST /tapes/:id/sync-push` | 1/24h per tape |
| All other endpoints | 60/min per user |

---

## R2 Upload Flow

```
iOS                          Workers API                    R2
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
 |                               |  Notify collaborators    |
 |  { order_index, expires_at } |                          |
 |<------------------------------|                          |
```

---

## Scheduled Jobs (Cron Triggers)

| Job | Cron | Handler |
|-----|------|---------|
| Expiry check | `0 * * * *` (hourly) | Delete R2 assets where `expires_at` has passed |
| Sync warning | `0 * * * *` (hourly) | Notify owner when clips within 48h of expiry have unsynced collaborators |
| Orphan cleanup | `0 3 * * *` (daily 03:00 UTC) | Delete R2 assets with no DB record older than 24h |
| Expired tape cleanup | `0 4 * * *` (daily 04:00 UTC) | Mark expired view-only tapes, flag for removal |
| Notification batch | `0 */3 * * *` (every 3h) | Batch and send accumulated notifications |
