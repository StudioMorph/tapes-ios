# Tape Player Transition Roadmap

## Objective
Build a composition-driven playback pipeline that delivers smooth, extensible transitions (none, crossfade, slide left/right, randomise) for tape previews while simplifying runtime state management.

---

## Phase 1 – Baseline & Analysis
1. **Capture Current Requirements**
   - Confirm desired transition catalogue (`.none`, `.crossfade`, `.slideLR`, `.slideRL`, `.randomise`).
   - Document audio behaviour expectations (e.g. volume ramps for crossfade, hard cuts otherwise).
2. **Audit Existing Player**
   - Verify current `TapePlayerView` wiring and UI requirements (full-screen playback, controls visibility).
   - Review tape model metadata needed for composition building (clip assets, durations, transition settings).
3. **Define Success Metrics**
   - No visual/audio hitching between clips.
   - Transitions selectable per boundary and deterministic for randomise mode.
   - Easily pluggable architecture for future transition styles.

---

## Phase 2 – Composition Pipeline
1. **Timeline Builder**
   - Create a dedicated module to assemble `AVMutableComposition` with video/audio tracks per clip.
   - Calculate transition overlaps based on selected style and duration clamps.
   - Expose structured metadata (start times, overlap windows, participating tracks).
2. **Video Composition Instructions**
   - Implement transition strategies:
     - `NoneTransition`: sequential instructions (cuts).
     - `CrossfadeTransition`: `setOpacityRamp` on outgoing/incoming layers.
     - `SlideTransition`: `setTransformRamp` for left/right motion of both layers.
   - Combine instructions into an `AVMutableVideoComposition` with appropriate frame duration/render size.
3. **Audio Mix**
   - Mirror overlaps in audio tracks.
   - Add `AVMutableAudioMixInputParameters` for crossfade volume ramps; default to hard cuts otherwise.
4. **Randomise Support**
   - Generate per-boundary transition styles before timeline assembly.
   - Ensure sequence is reproducible (seeded) when required.

---

## Phase 3 – Player Integration
1. **Composition Loader**
   - Build utility to transform a `Tape` model into `(AVPlayerItem, AVAudioMix?)`.
   - Handle clip source resolution (local URLs, PHAssets, images) with prefetch/caching where necessary.
2. **TapePlayerView Update**
   - Replace multi-player logic with single `AVPlayer` fed by the composition.
   - Maintain existing UI behaviours (full-screen playback, controls, progress) using composition timeline metadata.
3. **Error Handling & Fallbacks**
   - Detect composition build failures and fall back to simple sequential playback if needed.
   - Surface loading states and recoverable errors to the UI/logs.

---

## Phase 4 – Validation *(in progress)*
1. **Automated Checks**
   - ✅ Add unit tests around transition builder (timeline math, instruction generation).
     - `TapeCompositionBuilderTests` now synthesise short sample assets to validate crossfade timelines and horizontal slide motion.
   - ☐ Consider snapshot/video export tests for regression detection.
2. **Manual QA**
   - Verify each transition type visually/audibly on a representative set of clips (short, long, mixed media).
   - Stress-test randomise mode for repeatability.
3. **Performance Review**
   - Measure composition build time and memory impact for long tapes.
   - Optimise preloading or caching if necessary.

---

## Phase 5 – Extensibility & Cleanup
1. **Transition Strategy Protocol**
   - Formalise a protocol/enum driving instruction generation to simplify future additions.
2. **Documentation**
   - Record usage guidelines (how to add new transitions, constraints on media).
   - Update RUNBOOK with debugging tips for composition issues.
3. **Codebase Cleanup**
   - Remove deprecated runtime-transition code paths.
   - Ensure lint/tests pass and repository is ready for review.

---

## Status Tracking
- [x] Phase 1 – Baseline & Analysis
- [x] Phase 2 – Composition Pipeline
- [x] Phase 3 – Player Integration
- [ ] Phase 4 – Validation
- [ ] Phase 5 – Extensibility & Cleanup
