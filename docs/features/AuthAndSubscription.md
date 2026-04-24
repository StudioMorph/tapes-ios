# Authentication & Subscription

## Summary

Email/password authentication with JWT sessions, email verification via Resend, password reset with Universal Links, and StoreKit 2 subscription with a 3-day free trial and two paid tiers: **TAPES Plus** and **TAPES Together**.

## Purpose & Scope

- Gate the app behind email/password sign-in (no anonymous or skip option in current build)
- Email verification enforced post-registration via transactional email (Resend)
- Password reset flow via email link with Universal Link deep linking back to the app
- Enforce a 3-day free trial limited to 3 tapes
- Present a paywall after the trial expires
- Manage subscription lifecycle via StoreKit 2 (on-device)
- Two paid tiers: Plus (core premium) and Together (collaboration-focused)

## Architecture

### Authentication

#### Backend (Cloudflare Worker)

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `POST /auth/register` | POST | Public | Create account (name, email, password). Password hashed with bcrypt. Returns JWT. Sends verification email. |
| `POST /auth/login` | POST | Public | Email/password sign-in. Returns JWT + user (including `email_verified`). |
| `POST /auth/forgot-password` | POST | Public | Always returns 200 (timing-safe). If user exists, sends reset email with token link. |
| `POST /auth/reset-password` | POST | Public | Validates token, updates password hash, returns new JWT. |
| `GET /auth/validate-reset-token` | GET | Public | Checks token validity/expiry without consuming it. |
| `GET /auth/verify-email` | GET | Public | Browser-click handler. Sets `email_verified = 1`, sends silent push to device, returns confirmation HTML. |
| `POST /auth/resend-verification` | POST | Bearer JWT | Re-sends verification email. Invalidates previous tokens first. |
| `GET /users/me` | GET | Bearer JWT | Returns user profile including `email_verified` status. |

#### iOS Core Services (`Tapes/Core/`)

| File | Role |
|------|------|
| `Auth/AuthManager.swift` | Central auth state manager. Handles register, login, forgot/reset password, email verification state. Persists user metadata in UserDefaults, JWT in Keychain (via `TapesAPIClient`). |
| `Networking/TapesAPIClient.swift` | HTTP client for all API calls. Auth endpoints: register, login, forgotPassword, resetPassword, validateResetToken, resendVerification, getMe. JWT stored in Keychain. |
| `Notifications/PushNotificationManager.swift` | Handles `email_verified` silent push from backend to update local verification state instantly. |

#### iOS Views (`Tapes/Views/Auth/`)

| File | Role |
|------|------|
| `AuthView.swift` | Combined login/register screen with mode toggle. Fields: name (register only), email, password. Presents `ForgotPasswordView` as sheet. |
| `ForgotPasswordView.swift` | Email input → "Check your inbox" confirmation. |
| `ResetPasswordView.swift` | Receives token via deep link. Validates token on appear, accepts new password, commits session on success. |

### Email Verification Flow

1. **Register** sends a verification email via Resend with a link to `GET /auth/verify-email?token=…`.
2. User clicks link in email → browser hits the Worker endpoint.
3. Worker sets `email_verified = 1` in D1, marks the token as used.
4. Worker sends a **silent APNs push** (`action: "email_verified"`) to the user's registered device token.
5. Worker returns HTML confirmation page (`verifiedPageTemplate`) with an "Open Tapes" button linking to `tapes://verified`.
6. **iOS receives the update** via two redundant paths:
   - **Silent push** → `PushNotificationManager` calls `authManager.markEmailVerified()`.
   - **Deep link** → `ContentView` handles `tapes://verified` and calls `authManager.markEmailVerified()`.
7. On next login, `email_verified` is also returned in the login response as a safety net.

### Password Reset Flow

1. User taps "Forgot Password" → enters email → `POST /auth/forgot-password`.
2. Worker sends a reset email with link to `/t/reset-password?token=…` (Universal Link format).
3. **If opened on a device with Tapes installed:** Universal Link resolves → `ContentView.handleDeepLink` extracts the token → presents `ResetPasswordView`.
4. **If opened in a browser without the app:** Worker serves `resetPasswordFallbackTemplate` — a branded page explaining the user needs the Tapes app, with a "Download on the App Store" badge.
5. `ResetPasswordView` validates the token (`GET /auth/validate-reset-token`), accepts new password, calls `POST /auth/reset-password`, receives new JWT, and commits the session.

### Email Templates

All templates are defined in `tapes-api/src/lib/email-templates.ts`:

| Template | Usage |
|----------|-------|
| `baseLayout(content)` | Shared email wrapper with logo, footer. Logo served from R2 (`assets/Light_mode__glow.png`). |
| `verifyEmailTemplate(verifyUrl)` | "Verify your email" CTA button. |
| `resetPasswordTemplate(resetUrl)` | "Reset your password" CTA button. 1-hour expiry note. |
| `verifiedPageTemplate(appDeepLink)` | HTML page shown after successful verification. Dark/light mode aware with SVG logos. |
| `resetPasswordFallbackTemplate(appStoreId?)` | HTML page for browser-based reset link access. Dark/light mode aware, SVG lock icon, App Store badge. |

### Subscription

#### Core Services (`Tapes/Core/`)

| File | Role |
|------|------|
| `Subscription/SubscriptionManager.swift` | StoreKit 2 multi-product loading, purchasing, transaction listening, tier resolution |
| `Subscription/TrialManager.swift` | Install date tracking, 3-day free trial logic, tape count limits |
| `Subscription/EntitlementManager.swift` | Unified access-control layer combining subscription tiers + trial state |

#### Views (`Tapes/Views/`)

| File | Role |
|------|------|
| `Subscription/PaywallView.swift` | Full-screen paywall with billing toggle, three tier cards, and purchase actions |

#### Configuration

| File | Role |
|------|------|
| `Configuration/TapesProducts.storekit` | Local StoreKit testing configuration with subscription products |

## Data Flow

```
TapesApp
├── AuthManager (email/password, JWT session, email_verified state)
│   └── TapesAPIClient (Keychain JWT, all auth HTTP calls)
├── PushNotificationManager (silent push → markEmailVerified)
├── EntitlementManager
│   ├── SubscriptionManager (StoreKit 2, multi-tier)
│   └── TrialManager (install date + limits)
└── ContentView
    ├── AuthView (if not signed in)
    │   ├── ForgotPasswordView (sheet)
    │   └── ResetPasswordView (sheet, via deep link token)
    └── TapesListView (if signed in)
        └── PaywallView (sheet if trial expired)
```

## Access Levels

| Level | Condition | Capabilities |
|-------|-----------|--------------|
| `free` | Free tier or within 3 days of install | Max 3 tapes/month, 1 shared tape, watermark exports |
| `plus` | Active Plus subscription | Unlimited tapes, no watermarks, 12k music library, AI mood music, 1 collab TAPE/month |
| `together` | Active Together subscription | Everything in Plus, AI prompt music, unlimited collaborative tapes |

## Subscription Products

| Product ID | Tier | Billing |
|------------|------|---------|
| `com.tapes.plus.monthly` | Plus | Monthly |
| `com.tapes.plus.annual` | Plus | Annual (-30%) |
| `com.tapes.together.monthly` | Together | Monthly |
| `com.tapes.together.annual` | Together | Annual (-30%) |

Legacy alias `com.tapes.premium.monthly` maps to `com.tapes.plus.monthly` for backward compatibility.

## Security

- Passwords hashed with bcrypt (via `bcryptjs`, Workers-compatible).
- JWT signed with `JWT_SECRET` (Cloudflare Worker secret). Rotation procedure at `tapes-api/docs/runbooks/jwt-rotation.md`.
- Auth tokens (verify, reset) stored in `auth_tokens` D1 table with expiry and single-use enforcement.
- Forgot-password endpoint always returns 200 regardless of email existence (timing-safe).
- Device token registered via `PUT /users/me/device-token` for silent push delivery.

## Dependencies

- `bcryptjs` (Worker — password hashing, Workers-compatible)
- `Resend` REST API (Worker — transactional email, no SDK)
- `StoreKit` (Apple framework)
- No third-party iOS dependencies for auth

## Testing

- Use the `TapesProducts.storekit` configuration file in Xcode scheme settings for local StoreKit testing.
- `TrialManager.resetTrial()` available in DEBUG builds to reset the install date.
- Email verification can be tested by checking the Resend dashboard for sent emails.
- Reset password flow requires a valid email in D1 and a device with Universal Links configured.

## QA Considerations

- Verify register creates account and sends verification email
- Verify login returns correct `email_verified` status
- Verify email verification link works and updates app state (via push and/or deep link)
- Verify forgot password sends email and reset link opens `ResetPasswordView`
- Verify reset password with valid token updates password and signs user in
- Verify reset password fallback page renders correctly in browsers without the app
- Verify expired/used tokens are rejected with appropriate error messages
- Verify paywall displays correct prices for both monthly and annual billing
- Verify subscription purchase grants correct access level
- Verify restore purchases works across tiers

## Known Limitations
- On-device entitlement checking only; server-side subscription validation to be added later.
- Privacy Policy and Terms of Use URLs are placeholders.
- `APP_STORE_APP_ID` environment variable is currently empty; reset password fallback page links to generic App Store until set.
