# Backlog

Items to revisit when time allows. Not urgent, not blocking — just worth doing.

---

## Sharing

### 1. Preserve receiver's custom tape title on re-sync

**Context**: When a receiver renames a shared tape locally and later taps the same share link to pick up new clips, the download coordinator overwrites their custom title with the sender's title from the manifest.

**Fix**: Skip the title update during merge if a local tape already exists (returning receiver). The sender's title should only be applied on the initial download. The receiver's local rename is "theirs" to keep.

**Files likely involved**: `SharedTapeDownloadCoordinator.swift`

---

## App Settings

### 2. Create a dedicated settings view

**Context**: The app currently has no standalone settings screen. As features grow (sharing, sync, notifications), a dedicated settings view is needed to house user preferences.

---

### 3. Auto-update on Wi-Fi only toggle

**Context**: Collaborative tapes will auto-check for updates on app open. To avoid unexpected cellular data usage, add a "Auto-update on Wi-Fi only" toggle in the settings view. When enabled, manifest checks still happen on any connection but clip downloads are deferred until Wi-Fi.

**Depends on**: Backlog item #2 (settings view).

---
