# Email Auth Setup — IMPLEMENTED

> **Status: Fully implemented and deployed.** This plan has been executed. See `docs/features/AuthAndSubscription.md` for the current feature documentation.

# Email Auth Setup

## Email Service Provider

**Provider**: Resend (https://resend.com)
**Sending Domain**: studiomorph.co.uk (verified, DNS records active)
**Region**: Ireland (eu-west-1)
**DNS Provider**: GoDaddy

### API Key

Stored as Cloudflare Worker secret `RESEND_API_KEY` (deployed).

### Sending Address

`noreply@studiomorph.co.uk`

## Scope

Replace Sign in with Apple with email/password authentication.

### Server Endpoints (Cloudflare Worker)

| Endpoint | Purpose |
|----------|---------|
| `POST /auth/register` | Create account (name, email, password) |
| `POST /auth/login` | Sign in (email, password) |
| `POST /auth/forgot-password` | Send password reset email |
| `POST /auth/reset-password` | Set new password with reset token |
| `GET /auth/validate-reset-token` | Check token validity without consuming it |
| `GET /auth/verify-email` | Browser-click handler, sets `email_verified`, sends silent push |
| `POST /auth/resend-verification` | Re-send verification email (authenticated) |
| `GET /users/me` | Returns user profile including `email_verified` |

### D1 Schema Changes

- Add `password_hash TEXT` to `users` table
- Remove `apple_user_id` column (no longer needed)

### iOS Changes

- Removed `AuthenticationServices` / Sign in with Apple
- New screens: `AuthView` (login/register), `ForgotPasswordView`, `ResetPasswordView`
- `AuthManager` updated for email/password JWT flow with `email_verified` state
- `PushNotificationManager` handles `email_verified` silent push
- `ContentView` handles `tapes://verified` and `tapes://reset-password?token=…` deep links

### Dependencies

- `bcryptjs` (password hashing, compatible with Cloudflare Workers)
- Resend REST API (transactional emails, no SDK needed)

## DNS Records (Already Configured)

| Type | Name | Status |
|------|------|--------|
| TXT | resend._domainkey | Verified (DKIM) |
| MX | send | Verified (SPF) |
| TXT | send | Verified (SPF) |
| TXT | _dmarc | Optional |
