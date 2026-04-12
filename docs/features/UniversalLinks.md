# Universal Links (share URLs)

## Summary

HTTPS share links (`https://…/t/{share_id}`) open the Tapes app when installed, or a small web page with an App Store button when not. Custom scheme `tapes://t/{id}` still works.

## iOS

- **Associated Domains:** `applinks:tapes-api.hi-7d5.workers.dev` (see `Tapes.entitlements`).
- **Handling:** `TapesApp` resolves both `tapes://` and `https://…/t/…` via `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`.

## Backend

- **`/.well-known/apple-app-site-association`** — JSON for Apple’s crawler (no auth).
- **`GET /t/{shareId}`** — HTML landing (App Store + `tapes://` fallback).
- **`PUBLIC_SHARE_BASE`** — Canonical origin for `share_url` in `POST /tapes` (see `wrangler.jsonc`).
- **`APP_STORE_APP_ID`** — Numeric App Store id for the landing page and Smart App Banner (set in Cloudflare vars when the app is on the store).

## QA

- After changing entitlements, reinstall the app and open a share link from Notes or Messages.
- Set `APP_STORE_APP_ID` before release so the landing page points at your listing, not App Store search.
