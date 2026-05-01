# Account Deletion

In-app account and data deletion, compliant with Apple App Review Guideline 5.1.1(v).

## Purpose & Scope

Apple requires apps that offer account creation to also provide in-app account deletion. This feature gives users a clear, friction-appropriate path to request permanent removal of their account and all associated data, with a 7-day cooling-off period that auto-cancels if the user signs back in.

## Key UI Components

- **AccountTabView** — "Delete Account & Data" button positioned below "Sign Out" in the existing sign-out section.
- **DeleteAccountSheet** — Full confirmation sheet with:
  - Tapes logo
  - Explanation of the 7-day cooling-off period
  - Apple subscription management callout (users must cancel subscriptions separately via iOS Settings)
  - "No, I want to stay" (primary, prominent) and "Yes, delete my account and data" (destructive, bordered) buttons

## Data Flow

1. User taps "Delete Account & Data" → `DeleteAccountSheet` presented.
2. User confirms → `TapesAPIClient.requestAccountDeletion()` calls `POST /users/me/delete`.
3. Server sets `delete_scheduled_at = NOW + 7 days` on the user row and returns the timestamp.
4. iOS signs the user out immediately via `AuthManager.signOut()`.
5. If the user signs back in within 7 days, `handleLogin` clears `delete_scheduled_at` — deletion cancelled.
6. Daily cron (04:00 UTC) in `scheduled.ts` runs `runAccountDeletion()`:
   - Finds users where `delete_scheduled_at < NOW`.
   - Deletes all R2 assets (clips, thumbnails, live photo movies, background music) for owned tapes.
   - Cascade-deletes all DB rows: clips, download tracking, upload batches, pending notifications, tape members, tapes, and finally the user row.

## API

| Endpoint                | Method | Auth | Description                                     |
|-------------------------|--------|------|-------------------------------------------------|
| `POST /users/me/delete` | POST   | Yes  | Schedules account deletion in 7 days            |
| `GET /users/me`         | GET    | Yes  | Now includes `delete_scheduled_at` in response  |

## Testing / QA Considerations

- Verify the sheet appears from the Account tab and can be dismissed via "Cancel" or "No, I want to stay".
- Verify the destructive action calls the endpoint, signs the user out, and dismisses the sheet.
- Verify signing back in within 7 days clears `delete_scheduled_at` (check via `GET /users/me`).
- Verify the cron purge works after 7 days (can be tested by manually setting `delete_scheduled_at` to a past date in D1).
- Verify Apple subscription management link opens iOS Settings correctly.

## Migration

- `migrations/0014_account_deletion.sql` — adds `delete_scheduled_at TEXT` column to `users` table.
