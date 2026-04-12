# Share Modal (Phase 2)

## Summary

Bottom sheet presenting three sharing options: Share with Others, Export Tape, and Save to Device. Entry point is a share icon on each tape card, to the left of the settings icon.

## Purpose & Scope

The Share Modal is the user-facing entry point for all sharing and export functionality. It presents options in a clean, organised bottom sheet following the existing design language.

## Key UI Components

- **ShareModalView** — Bottom sheet with three sections, native navigation header with X close button
- **ShareFlowView** — Sub-sheet for configuring and executing a share (mode selection, expiry, invites)
- **Share icon** — `square.and.arrow.up` SF Symbol added to `TapeCardView` title row, left of settings icon

## Entry Points

1. Share icon on tape card title row (`TapeCardView`)
2. Passes through `TapesList` → `TapesListView` via `onShare` callback
3. Presented as `.sheet` from `TapesListView`

## Data Flow

```
Tap share icon → TapeCardView.onShare
    → TapesList.onShare(tape)
    → TapesListView.handleShare(tape)
    → Sets tapeToShare + showingShareModal
    → ShareModalView presented as sheet
    → User selects Share with Others
    → ShareFlowView presented as sub-sheet
    → User configures mode, expiry, invites
    → POST /tapes (create server record)
    → POST /tapes/:id/collaborators (for each invite)
    → ShareResult displayed with share link
    → User taps Share Link → UIActivityViewController
```

## Share Modes

- **View Only** — Recipients can play and AirPlay. Optional 7-day auto-expiry toggle.
- **Collaborative** — Recipients can contribute clips. Requires Together tier (gated in UI).

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
- Collaborative option gated behind Together tier
- Email validation on invite input
- Share link copy and share sheet both functional
- Error alert shown on API failure

## Related

- API Contract: `docs/plan/API_CONTRACT_V1.md`
- Sharing Spec: `docs/plan/TAPES_SHARE_SPEC_V1.md` (Section 2)
