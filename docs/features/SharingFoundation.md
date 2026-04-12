# Sharing Foundation (Phase 1)

## Summary

Backend API and iOS networking infrastructure for cloud-based tape sharing. Enables uploading tapes to Cloudflare R2, creating server records in D1, and generating `.tape` manifest files.

## Purpose & Scope

Phase 1 lays the plumbing for all sharing functionality. No user-facing sharing UI yet — this phase builds the API, networking client, upload pipeline, authentication flow, and deep link handling that all subsequent phases depend on.

## Architecture

### Backend (`tapes-api`)

- **Runtime:** Cloudflare Workers (TypeScript)
- **Database:** D1 (serverless SQLite) — 6 tables: `users`, `tapes`, `collaborators`, `clips`, `clip_download_tracking`, `notification_preferences`, `sync_push_log`
- **Storage:** R2 (object storage for media files)
- **Auth:** Apple identity token verification via JWKS, server-issued JWT (HMAC-SHA256, 7-day lifetime)
- **Cron jobs:** Hourly expiry check + sync warning, daily orphan cleanup + expired tape cleanup, 3-hourly notification batch

### iOS (`tapes-ios`)

- **`TapesAPIClient`** — Actor-based networking client. Keychain-stored JWT. Typed response models. Auto-retry on 401 via re-authentication.
- **`CloudUploadManager`** — `@MainActor ObservableObject`. Manages upload tasks with progress tracking, exponential backoff retry (max 3 attempts). Uploads directly to R2 via presigned URLs.
- **`TapeManifest`** — Complete `Codable` model matching the `.tape` JSON schema from the spec. Includes clips, collaborators, permissions, tape settings.
- **`KeychainHelper`** — Thin wrapper around Security framework for storing/retrieving the API access token securely.
- **`APIError`** — Typed error enum mapping server error codes to user-facing messages.

## Key UI Components

No new UI in Phase 1. Deep link handler wired into `TapesApp.onOpenURL`.

## Data Flow

```
Sign in with Apple → identityToken
    → POST /auth/apple (Workers verifies with Apple JWKS)
    → Server creates/updates user in D1
    → Returns JWT access token
    → Stored in Keychain via KeychainHelper

Share a tape:
    → POST /tapes (create server record)
    → POST /tapes/:id/clips (get presigned R2 upload URL)
    → PUT to R2 presigned URL (direct upload)
    → POST /tapes/:id/clips/:id/uploaded (confirm, create tracking)
    → GET /tapes/:id/manifest (full .tape JSON)
```

## Configuration

### Info.plist additions
- `tapes://` URL scheme (`CFBundleURLTypes`)
- `.tape` file type (`CFBundleDocumentTypes` + `UTExportedTypeDeclarations`)
- `remote-notification` background mode

### Entitlements addition
- `aps-environment: development` (push notifications)

## Testing / QA Considerations

- R2 bucket must be enabled in Cloudflare Dashboard before media uploads work
- D1 migrations applied locally; remote deployment pending
- Server JWT secret must be set as a Wrangler secret before deployment
- Apple JWKS verification requires network access to `appleid.apple.com`

## Related

- API Contract: `docs/plan/API_CONTRACT_V1.md`
- Sharing Spec: `docs/plan/TAPES_SHARE_SPEC_V1.md`
- Build Roadmap: `docs/plan/sharing-roadmap.md`
