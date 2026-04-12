# Authentication & Subscription

## Summary

Sign in with Apple authentication and StoreKit 2 subscription with a 3-day free trial and two paid tiers: **TAPES Plus** and **TAPES Together**, each available as monthly or annual billing.

## Purpose & Scope

- Gate the app behind optional sign-in (skippable)
- Enforce a 3-day free trial limited to 3 tapes
- Present a paywall after the trial expires
- Manage subscription lifecycle via StoreKit 2 (on-device)
- Two paid tiers: Plus (core premium) and Together (collaboration-focused)

## Architecture

### Core Services (`Tapes/Core/`)

| File | Role |
|------|------|
| `Auth/AuthManager.swift` | Sign in with Apple credential handling, session persistence via UserDefaults |
| `Subscription/SubscriptionManager.swift` | StoreKit 2 multi-product loading, purchasing, transaction listening, tier resolution |
| `Subscription/TrialManager.swift` | Install date tracking, 3-day free trial logic, tape count limits |
| `Subscription/EntitlementManager.swift` | Unified access-control layer combining subscription tiers + trial state |

### Views (`Tapes/Views/`)

| File | Role |
|------|------|
| `Auth/SignInView.swift` | Sign-in screen with Sign in with Apple button and skip option |
| `Subscription/PaywallView.swift` | Full-screen paywall with billing toggle, three tier cards, and purchase actions |

### Configuration

| File | Role |
|------|------|
| `Configuration/TapesProducts.storekit` | Local StoreKit testing configuration with subscription products |

## Data Flow

```
TapesApp
├── AuthManager (session state)
├── EntitlementManager
│   ├── SubscriptionManager (StoreKit 2, multi-tier)
│   └── TrialManager (install date + limits)
└── ContentView
    ├── SignInView (if not signed in)
    └── TapesListView (if signed in)
        └── PaywallView (sheet if trial expired)
```

## Access Levels

| Level | Condition | Capabilities |
|-------|-----------|-------------|
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

## Paywall Design

- **Header**: TAPES logo centred, close button (44pt, blurred material) top-left
- **Billing toggle**: Segmented control — Monthly (default) | Annually with -30% badge
- **Three tier cards** (8pt gap, 28pt corner radius, `#223246` background):
  - **Plus**: white CTA button, blue accent checkmarks, feature grid
  - **Together**: blue border (4pt), blue CTA button, hero "Unlimited collaborative TAPES" callout
  - **Free**: grey "This is you" button, red limitation markers

## Testing

- Use the `TapesProducts.storekit` configuration file in Xcode scheme settings for local testing
- `TrialManager.resetTrial()` available in DEBUG builds to reset the install date
- StoreKit Configuration allows simulating purchases, renewals, and cancellations without App Store Connect

## Dependencies

- `StoreKit` (Apple framework)
- `AuthenticationServices` (Apple framework)
- No third-party dependencies

## QA Considerations

- Verify paywall displays correct prices for both monthly and annual billing
- Verify billing toggle switches prices on all cards
- Verify Plus purchase grants Plus access level
- Verify Together purchase grants Together access level
- Verify tier resolution prioritises Together over Plus if both are active
- Verify restore purchases works across tiers
- Verify free card correctly reflects current user's state
- Verify account settings shows correct tier name (Free / Plus / Together)
- Verify transaction listener handles renewals and revocations across all product IDs

## Known Limitations

- Sign in with Apple requires the capability enabled in Apple Developer portal (pending account approval)
- On-device entitlement checking only; server-side validation to be added later
- Privacy Policy and Terms of Use URLs are placeholders
- StoreKit testing configuration needs updating with new product IDs
