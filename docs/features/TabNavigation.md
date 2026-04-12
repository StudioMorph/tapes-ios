# Tab Bar Navigation

## Summary

Native `TabView` with three tabs replacing the single-page app structure. Uses the iOS 18+ `Tab` struct API for automatic Liquid Glass treatment on iOS 26.

## Purpose & Scope

Scalable top-level navigation that separates personal tapes, shared content, and account management into distinct sections. Follows Apple HIG guidance: tab bars for top-level navigation between peer sections; segmented controls for filtering within a single section.

## Tabs

### Tab 1 — My Tapes (`film.stack`)
- Contains the existing `TapesListView` with all tape cards, camera capture, import, export
- Tapes logo in scroll view + inline nav bar on scroll
- Export progress indicator in toolbar

### Tab 2 — Shared (`person.2`)
- `SharedTapesView` with native segmented control: View Only | Collaborative
- Sign-in prompt for unauthenticated users
- Loading, empty, and populated states
- Pull-to-refresh via `.refreshable`
- Backed by `GET /tapes/shared` API endpoint

### Tab 3 — Account (`person.circle`)
- `AccountTabView` with `NavigationStack` and large title
- Sections: Account, Appearance, Hot Tips, About, Credits, Legal, Sign Out
- Sign in with Apple for unauthenticated users
- Tier display and subscription management link

## Key Components

| Component | File | Role |
|-----------|------|------|
| `MainTabView` | `Views/MainTabView.swift` | Root tab container |
| `TapesListView` | `Views/TapesListView.swift` | Tab 1 content (simplified) |
| `SharedTapesView` | `Views/Share/SharedTapesView.swift` | Tab 2 content |
| `AccountTabView` | `Views/AccountTabView.swift` | Tab 3 content |
| `SharedTapeItem` | `Models/SharedTapeItem.swift` | Data model for shared tapes |

## Data Flow

```
TapesApp
  └── ContentView (onboarding, entitlement refresh)
        └── MainTabView (TabView with selection binding)
              ├── Tab 1: TapesListView (NavigationStack)
              │     └── TapesList → TapeCardView
              ├── Tab 2: SharedTapesView (NavigationStack)
              │     └── API: GET /tapes/shared → [SharedTapeItem]
              └── Tab 3: AccountTabView (NavigationStack)
                    └── Form sections
```

## iOS 26 Liquid Glass

By using the native `TabView` with the `Tab` struct, the app automatically receives:
- Glass tab bar material
- Glass navigation bars on each tab's `NavigationStack`
- Glass segmented control in Tab 2
- Glass search bar (when added)

No custom glass styling is required.

## Migration Notes

- `AccountSettingsView` is preserved for backward compatibility (still used as a sheet elsewhere) but the primary account UI is now `AccountTabView`
- Hot Tips button overlay removed from `TapesListView`; Hot Tips is now accessible from Account tab
- `showOnboarding` binding flows from `ContentView` → `MainTabView` → `AccountTabView`

## Testing / QA Considerations

- Tab selection persists during the session
- Each tab's `NavigationStack` is independent (no cross-tab navigation bleed)
- Deep links should eventually switch to the Shared tab
- Onboarding full-screen cover appears above the tab bar
- All three tabs render correctly in both portrait and landscape
