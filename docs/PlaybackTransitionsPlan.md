# Tape Player Transition Revamp Plan

## Goals
- Support hard cut, crossfade, slide L→R, slide R→L transitions in the runtime player.
- Mirror behaviour with export pipeline (AVFoundation) to keep parity.
- Maintain existing UX features: Ken Burns for photos, scrubbing, next/prev, autoplay.
- Keep architecture testable with minimal global state.

## Stage Overview

### Stage 1 – Player Core Restructure
- Represent clips as `ClipPlaybackBundle` (media, duration, metadata).
- Maintain two bundles (current/upcoming) and a deterministic transition sequence.
- Single render pipeline with phase awareness (hard cut only). Confirm scrubbing/navigation still work.
- Prepare logging hooks for debugging transitions.

### Stage 2 – Crossfade Transitions ✅
- Dual-layer rendering with active + outgoing bundles.
- Crossfade animation engine with opacity and volume ramps for video and stills.
- Automatic fallback to hard cut when transition is disabled or duration is zero.

### Stage 3 – Slide Transitions ✅
- Implemented slide animations for incoming bundles with direction-aware offsets.
- Added combination logic (slide+fade) and ensured randomise picks directional variants.
- Controls/settings now surface transition selection clearly.

### Stage 4 – Regression & Export Sanity
- Manual verification: playback loops, scrubbing, orientation changes, settings update, empty tapes.
- Validate exporter still uses same TransitionType mapping.
- Document follow-ups (e.g., tests, logging, metrics).

## Risks & Mitigations
- AVPlayer coordination complexity → guard with detailed logging and fallback to hard cut on failure.
- Performance on large tapes → preload next bundle lazily, limit image decoding size.
- Audio desync → ensure both players share `preferredTimescale` and we pause/reset before transitions.

## Test Strategy
- Manual: start/pause, next/prev, scrub, randomise transitions, image-only reel, mixed media.
- Instrumentation: temporary debug overlay to show active transition/style (remove before ship).
