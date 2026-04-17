# Backlog

Items to revisit when time allows. Not urgent, not blocking — just worth doing.

---

## Sharing

### 1. Preserve receiver's custom tape title on re-sync

**Context**: When a receiver renames a shared tape locally and later taps the same share link to pick up new clips, the download coordinator overwrites their custom title with the sender's title from the manifest.

**Fix**: Skip the title update during merge if a local tape already exists (returning receiver). The sender's title should only be applied on the initial download. The receiver's local rename is "theirs" to keep.

**Files likely involved**: `SharedTapeDownloadCoordinator.swift`

---
