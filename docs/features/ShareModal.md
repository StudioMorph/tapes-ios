# Share Modal

## Summary

Single bottom-sheet modal presenting Export, Save Clips, and inline sharing. Entry point is the share icon on each tape card, to the left of the settings icon. Sharing now happens **inside** this modal — there is no secondary "Share this tape" push.

## Purpose & Scope

The Share Modal is the user-facing entry point for every tape action that leaves the app (export, save, share). The sharing section is embedded, so link + email management is one tap away from the tape card.

## Key UI Components

- **ShareModalView** — Bottom sheet with a native navigation header and X close button, sections for Export / Save Clips and the embedded sharing UI.
- **ShareLinkSection** — Inline sharing component embedded in `ShareModalView`:
  - `Viewing tape` / `Collaborating tape` role tabs.
  - `Secured by email` toggle.
  - Link pill with copy-to-clipboard icon and a system share sheet button.
  - Email compose field and an "Authorised users" chip list (only visible when `Secured by email` is on).
- **Share icon** — `square.and.arrow.up` SF Symbol on `TapeCardView` title row.

## Entry Points

1. Share icon on tape card title row (`TapeCardView`)
2. Passes through `TapesList` → `TapesListView` via `onShare` callback
3. Presented as `.sheet` from `TapesListView`

## Data Flow

```
Tap share icon → TapeCardView.onShare
    → TapesList.onShare(tape)
    → TapesListView.handleShare(tape)
    → ShareModalView presented as sheet
        → ShareLinkSection.bootstrapShareState()
            → GET /tapes/:id             (all 4 share IDs)
            → GET /tapes/:id/collaborators (scoped per share_variant)
        → User selects role / toggles Secured
            → currentVariant = f(role, secured)  — picks one of 4 share IDs
        → User taps Copy or Share → ensureTapeUploaded (uploads clips to R2 on first use)
        → User types email + taps Invite
            → ensureTapeUploaded (first time)
            → POST /tapes/:id/collaborators { email, share_variant }
            → chip appears in "Authorised users" for that variant
        → User taps chip × to revoke
            → DELETE /tapes/:id/collaborators/:email?share_variant=…
```

## Share Variants (2 × 2)

|                 | Unprotected (open)   | Protected (email)       |
|-----------------|----------------------|--------------------------|
| **View-only**   | `view_open`          | `view_protected`         |
| **Collaborative** | `collab_open`      | `collab_protected`       |

All four IDs are minted server-side on tape creation (`tapes.ts → ensureAllShareIds`) and surfaced in `CreateTapeResponse` / `TapeInfo`. Each variant has an **independent invite list** — toggling `Secured by email` off does not drop the protected invite list; it simply reveals the unprotected URL.

## Design Tokens Used

- Backgrounds: `Tokens.Colors.primaryBackground`, `secondaryBackground`
- Text: `Tokens.Colors.primaryText`, `secondaryText`, `tertiaryText`
- Accent: `Tokens.Colors.systemBlue`
- Spacing: `Tokens.Spacing.s`, `m`, `l`, `xl`, `xxl`
- Radius: `Tokens.Radius.card`, `thumb`
- Typography: `Tokens.Typography.caption`, `body`
- Hit targets: All interactive elements meet 44pt minimum

## Testing / QA Considerations

- Share icon should be disabled (tertiary text colour) on empty tapes
- Email validation on invite input (single email per Invite tap, sent immediately)
- First invite / Share link / Copy action on a never-shared tape must trigger the R2 upload
- Subsequent invites reuse the cached `CreateTapeResponse` — no re-upload
- Switching role tabs or the `Secured by email` toggle must swap which of the 4 share IDs is shown
- Revoking a chip only removes that user from the **currently-selected variant**
- Error alert shown on API failure
- Already-rebuilt tapes on a recipient device are **not** recalled when the inviter revokes — we can only block future downloads / contributions

## Related

- API Contract: `docs/plan/API_CONTRACT_V1.md`
- Sharing Spec: `docs/plan/TAPES_SHARE_SPEC_V1.md` (Section 2)
