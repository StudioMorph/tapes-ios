# Authentication & Subscription

## Summary

Sign in with Apple authentication and StoreKit 2 subscription with a 3-day free trial, £0.99 introductory offer (7 days), and £2.99/month auto-renewable subscription.

## Purpose & Scope

- Gate the app behind optional sign-in (skippable)
- Enforce a 3-day free trial limited to 3 tapes
- Present a paywall after the trial expires
- Manage subscription lifecycle via StoreKit 2 (on-device)
- Unlock unlimited tapes and future premium features for subscribers

## Architecture

### Core Services (`Tapes/Core/`)

| File | Role |
|------|------|
| `Auth/AuthManager.swift` | Sign in with Apple credential handling, session persistence via UserDefaults |
| `Subscription/SubscriptionManager.swift` | StoreKit 2 product loading, purchasing, transaction listening, entitlement checking |
| `Subscription/TrialManager.swift` | Install date tracking, 3-day free trial logic, tape count limits |
| `Subscription/EntitlementManager.swift` | Unified access-control layer combining subscription + trial state |

### Views (`Tapes/Views/`)

| File | Role |
|------|------|
| `Auth/SignInView.swift` | Sign-in screen with Sign in with Apple button and skip option |
| `Subscription/PaywallView.swift` | Full-screen paywall with features, pricing, and purchase actions |

### Configuration

| File | Role |
|------|------|
| `Configuration/TapesProducts.storekit` | Local StoreKit testing configuration with subscription product and intro offer |

## Data Flow

```
TapesApp
├── AuthManager (session state)
├── EntitlementManager
│   ├── SubscriptionManager (StoreKit 2)
│   └── TrialManager (install date + limits)
└── ContentView
    ├── SignInView (if not signed in)
    └── TapesListView (if signed in)
        └── PaywallView (full-screen cover if trial expired)
```

## Access Levels

| Level | Condition | Capabilities |
|-------|-----------|-------------|
| `freeTrial` | Within 3 days of install, not subscribed | Max 3 tapes |
| `trialExpired` | Past 3 days, not subscribed | Paywall shown, app blocked |
| `premium` | Active subscription | Unlimited tapes, all features |

## Subscription Product

- **Product ID**: `com.tapes.premium.monthly`
- **Price**: £2.99/month
- **Intro offer**: £0.99 for 7 days (pay-up-front)
- **Group**: `Tapes Premium`

## Testing

- Use the `TapesProducts.storekit` configuration file in Xcode scheme settings for local testing
- `TrialManager.resetTrial()` available in DEBUG builds to reset the install date
- StoreKit Configuration allows simulating purchases, renewals, and cancellations without App Store Connect

## Dependencies

- `StoreKit` (Apple framework)
- `AuthenticationServices` (Apple framework)
- No third-party dependencies

## QA Considerations

- Verify Sign in with Apple flow completes and persists across app launches
- Verify skip bypasses auth and enters the app
- Verify free trial limits tape creation to 3
- Verify paywall appears after 3-day trial expires
- Verify subscription purchase unlocks unlimited tapes
- Verify restore purchases works
- Verify transaction listener handles renewals and revocations

## Known Limitations

- Sign in with Apple requires the capability enabled in Apple Developer portal (pending account approval)
- On-device entitlement checking only; server-side validation to be added later
- Privacy Policy and Terms of Use URLs are placeholders
