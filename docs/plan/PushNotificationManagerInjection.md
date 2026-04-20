# Push Notification Manager Injection

**Status:** draft, awaiting approval. **Deferred** — this is a post-launch cleanup, not a pre-release blocker.
**Scope:** iOS only. Medium refactor.
**Risk:** medium-high. Touches the singleton that handles every incoming APNs message and background push. Bugs here cause silent notification drops.
**Deploy posture:** ship with a full regression test on two devices.

---

## Problem

[Tapes/Core/Notifications/PushNotificationManager.swift](../../Tapes/Core/Notifications/PushNotificationManager.swift) is the project's one intentional singleton:

```swift
static let shared = PushNotificationManager()

var apiClient: TapesAPIClient?
var navigationCoordinator: NavigationCoordinator?
var syncChecker: TapeSyncChecker?
var tapesProvider: (() -> [Tape])?
```

Four dependencies, all mutable, assigned from different places at different times:

- `apiClient` — set in `TapesApp.body.task` ([TapesApp.swift:43](../../Tapes/TapesApp.swift:43))
- `navigationCoordinator` — same place ([TapesApp.swift:44](../../Tapes/TapesApp.swift:44))
- `syncChecker` — set in `MainTabView.body.task` ([MainTabView.swift:69](../../Tapes/Views/MainTabView.swift:69))
- `tapesProvider` — set in `MainTabView.body.task` ([MainTabView.swift:70](../../Tapes/Views/MainTabView.swift:70))

A push arriving before `MainTabView.task` fires (say, cold launch from a tapped notification) will:

- Read `apiClient` as `nil` (TapesApp hasn't run `task` yet — race) → log `"dependencies not ready, skipping"` → silently drop the push.
- OR, if `TapesApp.task` has run but `MainTabView.task` hasn't → read `syncChecker` as `nil` → same.

This is flaky. Works in practice because cold launches usually beat the first push by enough margin. Fails in rare cases that are impossible to reproduce on demand.

The singleton is also hard to test: no way to inject a mock `TapesAPIClient` or assert on `syncChecker` behaviour.

---

## Why deferred

This is correctable anytime, and the current behaviour isn't a user-visible bug most of the time. Fixing it properly means:
- Removing the `.shared` singleton.
- Passing a manager instance through `.environmentObject`.
- Updating `AppDelegate` to look up the manager through a different pathway (AppDelegate doesn't have access to `.environmentObject`).

That last part is the sticky one — `UIApplicationDelegate` callbacks for APNs registration and background push don't naturally compose with SwiftUI's environment. The fix involves some ceremony.

For pre-launch: the singleton works. Documented as the exception to "no singletons" in the feedback memory. Moving on.

For post-launch: worth the cleanup for testability and for removing the race.

---

## Design (for when we do this)

Two options.

### Option A — Keep the singleton, but fix the race

Add a barrier that waits for dependencies before processing pushes. When a push arrives before dependencies are set, queue it; process the queue when dependencies are ready.

```swift
final class PushNotificationManager {
    private var pendingPushes: [(userInfo: [AnyHashable: Any], completionHandler: (UIBackgroundFetchResult) -> Void)] = []
    private let dependencyLock = NSLock()
    private var isReady = false

    func setDependencies(api: TapesAPIClient, nav: NavigationCoordinator, checker: TapeSyncChecker, tapesProvider: @escaping () -> [Tape]) {
        dependencyLock.lock()
        defer { dependencyLock.unlock() }
        self.apiClient = api
        self.navigationCoordinator = nav
        self.syncChecker = checker
        self.tapesProvider = tapesProvider
        self.isReady = true
        let drainable = pendingPushes
        pendingPushes = []
        for item in drainable {
            handleBackgroundPush(userInfo: item.userInfo, completionHandler: item.completionHandler)
        }
    }

    func handleBackgroundPush(userInfo: [AnyHashable: Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        dependencyLock.lock()
        if !isReady {
            pendingPushes.append((userInfo, completionHandler))
            dependencyLock.unlock()
            return
        }
        dependencyLock.unlock()
        // ...original handling...
    }
}
```

Pros: minimal refactor. Keeps the singleton.
Cons: still a singleton. Still hard to test. Still accretes state.

### Option B — Real refactor

Make `PushNotificationManager` a normal class. Construct it in `TapesApp` after the other env objects. Inject dependencies at construction (no optionals). Pass to `AppDelegate` via a shared reference that's set during `TapesApp.init`.

```swift
@main
struct TapesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var tapeStore = TapesStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var entitlementManager = EntitlementManager()
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var syncChecker = TapeSyncChecker()

    private let apiClient = TapesAPIClient()
    private let pushManager: PushNotificationManager

    init() {
        let api = apiClient
        let nav = NavigationCoordinator()
        let sync = TapeSyncChecker()
        self.pushManager = PushNotificationManager(
            api: api,
            navigationCoordinator: nav,
            syncChecker: sync,
            tapesProvider: { [weak tapeStore] in tapeStore?.tapes ?? [] }
        )
        AppDelegate.pushManager = pushManager   // ← static reference so AppDelegate can call it
        // ...rest unchanged
    }
}
```

The `AppDelegate` side:

```swift
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var pushManager: PushNotificationManager?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.pushManager?.handleDeviceToken(deviceToken)
    }
    // ...
}
```

The static ref in `AppDelegate` is still a singleton-ish pattern but it's scoped to the app process and gated through a typed, immutable dependency graph. Tests can construct a `PushNotificationManager` with mocks directly.

Pros: clean dependencies. Testable. No race.
Cons: bigger diff. `AppDelegate` has a static. We've swapped one singleton for a different, smaller one — the static ref — but it's immutable after launch.

### Recommendation

**Option B** when we do this. Option A is a band-aid; the right fix is to break the singleton.

---

## Risks

- **Breaking APNs registration on the first launch after the change.** The test is: install fresh build, grant notifications, confirm device token lands on server (check server logs for `PUT /users/me/device-token`).
- **Breaking the tap-opens-tape flow.** Test: Isabel sends a share, you tap the notification on lock screen, confirm Tapes opens to the Shared tab with the right tape resolved.
- **Breaking background push.** Test: Isabel uploads a clip, you watch your phone's badge increment within seconds without opening the app.
- **Any tests or previews that reference `PushNotificationManager.shared` break.** Grep, fix call sites, confirm previews still build.

---

## Verification

Full APNs regression on two devices:

1. Fresh install → device token registers on server.
2. Isabel shares a tape → you get invite notification → tap → app opens to shared tape.
3. Isabel uploads a clip → you get contribution push → badge updates without opening app.
4. Sync-push from Isabel's owner tape → you get notification.
5. Expiry warning cron fires for an owner tape → that owner gets notification.

Any skipped step = regression. Revert and reassess.

---

## Deploy

iOS-only, ships with the build that includes the change.

---

## Open questions

None worth blocking on. Pick Option B when we do this, test thoroughly, done.
