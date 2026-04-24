# Email Auth Setup

## Email Service Provider

**Provider**: Resend (https://resend.com)
**Sending Domain**: studiomorph.co.uk (verified, DNS records active)
**Region**: Ireland (eu-west-1)
**DNS Provider**: GoDaddy

### API Key

Stored as Cloudflare Worker secret `RESEND_API_KEY` (deployed).

### Sending Address

`noreply@studiomorph.co.uk` (or `tapes@studiomorph.co.uk` — to be decided)

## Scope

Replace Sign in with Apple with email/password authentication.

### Server Endpoints (Cloudflare Worker)

| Endpoint | Purpose |
|----------|---------|
| `POST /auth/register` | Create account (name, email, password) |
| `POST /auth/login` | Sign in (email, password) |
| `POST /auth/forgot-password` | Send password reset email |
| `POST /auth/reset-password` | Set new password with reset token |

### D1 Schema Changes

- Add `password_hash TEXT` to `users` table
- Remove `apple_user_id` column (no longer needed)

### iOS Changes

- Remove `AuthenticationServices` / Sign in with Apple
- New screens: Sign In, Create Account, Forgot Password
- Update `AuthManager` for email/password JWT flow

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
