# Root-Level File Reorganisation

**Status:** draft, awaiting approval. **Deferred** — tidying, not a blocker.
**Scope:** iOS only. Pure move-and-rename, no behaviour change.
**Risk:** low — but big diffs are annoying to review and git blame gets noisy for anyone who works on these files later.
**Deploy posture:** ships with next iOS build; no verification needed beyond "does it still build and run".

---

## Problem

The cursor rules document the intended folder structure:

```
Tapes/
├─ App/
│  └─ Features/Tape/...
├─ Core/{Models,Persistence,Media,Thumbnails,Logging}
├─ DesignSystem/
└─ Tests/
```

Reality is different. Several files live at the root of `Tapes/` that predate the Design System structure and were never moved:

- [Tapes/Carousel.swift](../../Tapes/Carousel.swift)
- [Tapes/FAB.swift](../../Tapes/FAB.swift)
- [Tapes/ClipEditSheet.swift](../../Tapes/ClipEditSheet.swift)
- [Tapes/Thumbnail.swift](../../Tapes/Thumbnail.swift)
- [Tapes/CastManager.swift](../../Tapes/CastManager.swift)
- [Tapes/AppearanceConfigurator.swift](../../Tapes/AppearanceConfigurator.swift)

None of these are broken. They work. They're just in the wrong place.

The cursor rules also say: *"For existing screens that predate the Design System, DO NOT rewrite or migrate unless I explicitly ask."* Moving-without-rewriting is different from rewriting. This plan moves only; no code inside the files changes.

---

## Proposed moves

| Current | New |
|---|---|
| `Tapes/Carousel.swift` | `Tapes/Components/Carousel.swift` |
| `Tapes/FAB.swift` | `Tapes/Components/FAB.swift` |
| `Tapes/ClipEditSheet.swift` | `Tapes/Components/ClipEditSheet.swift` |
| `Tapes/Thumbnail.swift` | `Tapes/Components/Thumbnail.swift` |
| `Tapes/CastManager.swift` | `Tapes/Core/Casting/CastManager.swift` |
| `Tapes/AppearanceConfigurator.swift` | `Tapes/Core/AppearanceConfigurator.swift` |

`Components/` already exists and houses similar files (AirPlayButton, ClipCarousel, ThumbnailView, etc.). These root-level files fit there.

`Core/Casting/` is new; it's where the cast manager belongs by theme. Alternative: `Tapes/Casting/`. Minor.

`AppearanceConfigurator` is more ambiguous — it's not really "Core" in the models/persistence sense. Could also live in `App/`. I'd put it in `Core/` (it's UIKit boilerplate that affects global app appearance).

---

## Why defer

1. Xcode project file (.pbxproj) churn on file moves is noisy and merge-conflict prone. Doing this during active feature work competes with everything else.
2. Zero user-visible benefit. Pure hygiene.
3. Gets caught by any future review ("why is Thumbnail.swift at the root?"), which is the natural time to do it.

Suggest doing this as a batch after launch prep is done — a "folder cleanup" PR when the codebase is otherwise stable.

---

## Risks

- **Xcode project file conflicts** if someone else is editing `.pbxproj` during the move. Single PR, fast turnaround.
- **Git blame gets a "file moved" entry.** That's unavoidable and doesn't really harm anything — git respects file renames with `--follow`.
- **References in docs** (RUNBOOK.md mentions paths). Search-and-update.

---

## Verification

1. Move the files with Xcode's "Move…" option (it updates the `.pbxproj` correctly).
2. Build. Must succeed on first try.
3. Run. App launches, all flows still work.
4. Grep the codebase for the old paths (`Tapes/Carousel.swift` etc.) — all references should be updated. Docs too.
5. `git diff --stat` — expect ~6 file renames plus a modified `.pbxproj`. Nothing else.

---

## Deploy

iOS-only, next build.

---

## Open questions

Minor: where does `AppearanceConfigurator` belong? I said `Core/`. Could be anywhere reasonable. Defer the bike-shed, pick when we do the move.
