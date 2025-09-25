# Transitions — Single Source of Truth

- **Randomise**: seeded per tape (UUID) → deterministic sequence.
- **Duration clamp**: Randomised transitions cap at **0.5s**.
- **Preview**: visual overlays simulate Crossfade/Slides using the same sequence.
- **Export (iOS)**: AVFoundation with **opacity/transform ramps** + **audio fades**.
- **Export (Android)**: FFmpegKit with `xfade=fade|slideleft|slideright` and `acrossfade`, normalized to **1080p** canvas.
