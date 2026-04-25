# Notification Delivery Preferences

Users can choose how tape update notifications are delivered: immediately or as periodic digest summaries.

## Purpose & Scope

Gives receivers control over notification frequency. Senders always generate notifications; the delivery timing depends on each recipient's preference.

## Delivery Modes

| Mode | Raw value | Behaviour |
|---|---|---|
| Immediate | `auto` | Push sent the moment an event occurs (default). |
| Hourly Digest | `hourly` | Queued and flushed every hour. |
| Twice Daily | `twice_daily` | Flushed at 12 pm and 6 pm local time. |
| Once Daily | `once_daily` | Flushed at 6 pm local time. |

"Local time" is derived from the user's IANA timezone, synced from the iOS device.

## Data Model

### Users table additions

- `delivery_mode TEXT NOT NULL DEFAULT 'auto'` — one of `auto`, `hourly`, `twice_daily`, `once_daily`.
- `timezone TEXT` — IANA timezone identifier (e.g. `Europe/London`).

### New table: `pending_notifications`

Holds queued notifications for non-auto users until the cron flushes them.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | Auto-increment. |
| `user_id` | TEXT FK | References `users(user_id)`. |
| `tape_id` | TEXT | The tape this notification relates to. |
| `title` | TEXT | Notification title. |
| `body` | TEXT | Notification body. |
| `payload` | TEXT | Full push payload as JSON. |
| `created_at` | TEXT | ISO 8601 timestamp. |

Migration: `0013_notification_delivery_prefs.sql`.

## API

### `PUT /users/me/notification-preference` (authenticated)

**Request:**
```json
{ "delivery_mode": "hourly", "timezone": "Europe/London" }
```

**Response (200):**
```json
{ "delivery_mode": "hourly", "timezone": "Europe/London" }
```

Validation rejects unknown `delivery_mode` values with 422.

### `GET /users/me` (updated)

Now includes `delivery_mode` and `timezone` in the response.

## Backend Flow

1. `notifyTapeParticipants` checks each recipient's `delivery_mode`.
   - `auto` → immediate push (existing behaviour).
   - Anything else → `INSERT INTO pending_notifications`.
2. Hourly cron (`0 * * * *`) calls `flushDigestNotifications`.
3. For each user with pending rows, the cron checks whether it's time to flush based on `delivery_mode` and their local hour (derived from `timezone`).
4. Digest push: single notification summarising total updates and tape count. All flushed rows are deleted.

## iOS UI

Located in `PreferencesView` under **Notification Delivery**.

- Standard `Picker` with `.automatic` style (menu on iOS).
- Selection stored locally via `@AppStorage("tapes_delivery_mode")`.
- On change, fires `PUT /users/me/notification-preference` with the mode and `TimeZone.current.identifier`.
- If the network call fails, a `pendingSync` flag is set. An `NWPathMonitor` retries when connectivity recovers.
- On view appear, the server preference is loaded via `getMe` to ensure local state is in sync.

## Key Components

- `Tapes/Views/Settings/PreferencesView.swift` — delivery mode picker and sync logic.
- `Tapes/Core/Networking/TapesAPIClient.swift` — `updateNotificationPreference()`, `NotificationPreferenceResponse`, updated `UserInfo`.
- `tapes-api/src/routes/users.ts` — `updateNotificationPreference` handler, updated `getMe`.
- `tapes-api/src/lib/apns.ts` — `notifyTapeParticipants` now queues non-auto recipients.
- `tapes-api/src/routes/scheduled.ts` — `flushDigestNotifications`, `shouldFlush`, `getLocalHour`.

## Testing & QA

1. Set delivery mode to each option and verify it persists after app restart.
2. Trigger a tape update from another user; verify auto delivers instantly.
3. Set to hourly; trigger updates; verify they arrive as a single digest on the next cron run.
4. Kill the app, change preference — on next launch, verify it syncs.
5. Toggle airplane mode, change preference, restore connectivity — verify retry succeeds.
