# Tape Player - User Experience Description
## Complete User Journey from Scratch Rebuild

---

## Opening the Player

### Initial State
**User Action**: Taps "Play" on a tape card

**What Happens**:
1. Screen transitions to full-screen black player
2. Immediately shows glass "Loading tape..." overlay with spinner
3. Close button (X) appears in top-left corner
4. Clip counter appears in top-right (e.g., "1 of 12")

**User Sees**:
- Black screen
- Centered loading spinner with "Loading tape..." text
- Header with close button and clip counter
- Controls are hidden (will appear after loading)

**Behind the Scenes** (invisible to user):
- All clips start loading in parallel (video from Photos, images encoding to video)
- iCloud assets download if needed (network access enabled)
- Composition builds with all clips and transitions
- Ready for playback in 1-3 seconds (depending on iCloud content)

---

## Loading States

### Fast Load (Local Clips)
**User Sees**: "Loading tape..." for 0.5-1 second
**What Happens**: All clips are local, load instantly, composition builds quickly
**Result**: Playback starts smoothly within 1 second

### Slow Load (iCloud Clips)
**User Sees**: "Loading tape..." for 2-3 seconds
**What Happens**: Some clips are in iCloud, downloading in parallel
**Result**: Playback starts once all clips ready (or after timeout, skips failed clips)

### Mixed Load (Local + iCloud)
**User Sees**: "Loading tape..." for 1-2 seconds
**What Happens**: Local clips ready immediately, iCloud clips download in parallel
**Result**: Playback starts once all ready

### Error During Load
**User Sees**: "Loading tape..." then error message appears
**Error Examples**:
- "Photos access is required to play this tape" (with action to open Settings)
- "Some clips are unavailable" (continues with available clips)
- "Network timeout" (retries automatically)

---

## Playback Experience

### Starting Playback

**User Action**: Player loads and automatically starts playing

**User Sees**:
- Loading overlay disappears
- Video/image appears full-screen
- Playback starts smoothly
- Controls fade out after 3 seconds

**What's Playing**:
- First clip plays (video or image)
- Transitions render seamlessly between clips
- Audio plays if clips have audio tracks
- Ken Burns effect on images (subtle zoom/pan)

### During Playback

**User Sees**:
- Full-screen video/images
- Smooth transitions at clip boundaries
- No glitches, no jumping, no stalling
- Continuous playback as if it's one video

**Transitions**:
- **None**: Instant cuts between clips (no transition)
- **Crossfade**: Smooth fade between clips (overlapping blend)
- **Slide L→R**: Clip slides in from right, outgoing slides left
- **Slide R→L**: Clip slides in from left, outgoing slides right
- **Randomise**: Mix of transitions (different each boundary, but deterministic per tape)

**Behind the Scenes**:
- Single composition plays from start to finish
- All transitions pre-rendered in composition
- No composition swapping during playback
- Smooth 60fps playback on capable devices

---

## Controls Interaction

### Revealing Controls

**User Action**: Taps anywhere on the screen during playback

**User Sees**:
- Controls fade in smoothly
- Header appears (close button, clip counter)
- Progress bar at bottom
- Play/Pause button, Previous/Next buttons

**Controls Layout**:
```
┌─────────────────────────────┐
│ [X]               "3 of 12" │  ← Header
│                             │
│                             │
│                             │  ← Video Area
│                             │
│                             │
│  ━━━━━━━━━━━━━━━━━━━━━━━━  │  ← Progress Bar
│  [⏮]  [⏯]  [⏭]             │  ← Controls
└─────────────────────────────┘
```

### Hiding Controls

**User Action**: Taps screen again OR waits 3 seconds

**User Sees**:
- Controls fade out smoothly
- Header fades out
- Only video visible (immersive full-screen)

### Progress Bar

**User Sees**:
- Horizontal bar showing playback progress
- White circle indicating current position
- Bar fills left-to-right as tape plays
- Time indicators (e.g., "1:23 / 4:56")

**User Action**: Drags the circle (scrubbing)

**What Happens**:
- Playback pauses
- Video frame updates as user drags
- Time indicator updates in real-time
- When released, playback jumps to new position
- If in middle of transition, seeks to nearest clip boundary

**Scrubbing Behavior**:
- Smooth frame preview while dragging
- Accurate positioning (no lag)
- Immediate response to touch

---

## Playback Controls

### Play/Pause

**User Action**: Taps center play/pause button

**Play State**:
- Icon shows pause (⏸)
- Playback continues
- Controls auto-hide after 3 seconds

**Pause State**:
- Icon shows play (▶)
- Playback stops
- Controls stay visible (no auto-hide when paused)
- Current frame remains visible

### Previous Clip

**User Action**: Taps previous button (⏮)

**What Happens**:
- Playback immediately jumps to start of current clip
- If already at start, jumps to start of previous clip
- Playback continues automatically
- Smooth transition (if enabled) plays normally

**Edge Case**: At first clip
- Button disabled (grayed out)
- Tapping does nothing

### Next Clip

**User Action**: Taps next button (⏭)

**What Happens**:
- Playback immediately jumps to start of next clip
- Playback continues automatically
- Smooth transition (if enabled) plays normally

**Edge Case**: At last clip
- Button disabled (grayed out)
- Tapping does nothing

**Clip Navigation**:
- Works instantly (no loading delay)
- Transitions play when jumping between clips
- Clip counter updates immediately

---

## Different Media Types

### Video Clips

**User Experience**:
- Full-screen video playback
- Audio plays if video has audio track
- Smooth transitions at boundaries
- Normal playback speed (1x)
- Respects clip rotation settings
- Respects clip scale mode (fit/fill)

**Behavior**:
- Plays at original frame rate
- Audio syncs perfectly with video
- No stuttering or lag
- Handles various video formats (MP4, MOV, etc.)

### Image Clips

**User Experience**:
- Image displays full-screen
- Plays for clip duration (default 4 seconds)
- Ken Burns effect (subtle zoom and pan)
- Smooth transitions at boundaries
- No audio (images don't have audio)

**Ken Burns Effect**:
- Starts zoomed in slightly (1.05x)
- Ends zoomed in more (1.1x)
- Subtle pan across image
- Smooth animation over clip duration
- Respects Reduce Motion (static image if enabled)

**Image Handling**:
- Image encoded to video on-the-fly
- Temporary video file created
- Cleans up after playback
- Handles rotation settings
- Handles scale mode (fit/fill)

---

## Transition Types

### None Transition

**User Experience**:
- Instant cut from one clip to next
- No overlap between clips
- Hard cut (no blending)
- Fastest playback (no transition overhead)

**Visual**: Clip A ends → instant cut → Clip B starts

### Crossfade Transition

**User Experience**:
- Smooth fade between clips
- Outgoing clip fades out while incoming fades in
- Overlap duration = transition duration setting
- Audio fades out/in smoothly

**Visual**: Clip A fades out (opacity 1.0 → 0.0) while Clip B fades in (opacity 0.0 → 1.0)
**Duration**: Typically 0.5-1.0 seconds

### Slide L→R (Left to Right)

**User Experience**:
- Incoming clip slides in from right
- Outgoing clip slides out to left
- Both clips visible during transition
- Opacity fade on both clips

**Visual**: 
- Clip A slides left (transform: (0,0) → (-width, 0))
- Clip B slides in from right (transform: (width, 0) → (0, 0))
- Both fade during transition

### Slide R→L (Right to Left)

**User Experience**:
- Incoming clip slides in from left
- Outgoing clip slides out to right
- Both clips visible during transition
- Opacity fade on both clips

**Visual**: 
- Clip A slides right (transform: (0,0) → (width, 0))
- Clip B slides in from left (transform: (-width, 0) → (0, 0))
- Both fade during transition

### Randomise Transition

**User Experience**:
- Different transition at each clip boundary
- Sequence is deterministic (same every time for same tape)
- Mixes: none, crossfade, slide L→R, slide R→L
- Transition duration clamped to 0.5s max (snappy feel)

**Visual**: Each boundary has a different transition style
**Deterministic**: Same tape always has same sequence (matches export)

---

## Scenarios & Edge Cases

### Playing a Tape with Only Videos

**User Experience**:
- All clips are video files
- Audio plays from clips that have audio
- Smooth video-to-video transitions
- Standard playback experience

### Playing a Tape with Only Images

**User Experience**:
- All clips are images
- Each image plays for its duration with Ken Burns
- Smooth image-to-image transitions
- No audio throughout tape

### Playing a Mixed Tape (Videos + Images)

**User Experience**:
- Videos play normally with audio
- Images play with Ken Burns (no audio)
- Transitions work seamlessly between videos and images
- Audio fades appropriately at boundaries

### Playing a Tape with iCloud Assets

**User Experience**:
- "Loading tape..." appears (may take 2-3 seconds)
- Progress indicator shows activity
- Once loaded, playback starts normally
- All clips ready before playback begins

**If Network Slow**:
- Loading takes longer (up to 10 seconds)
- User sees loading state
- Once ready, playback is smooth (no stalling)

**If Network Fails**:
- Error message appears
- Option to retry
- Or play with available clips (skip failed ones)

---

## Seeking & Scrubbing

### Scrubbing to Different Position

**User Action**: Drags progress bar

**User Sees**:
- Progress bar updates in real-time
- Time indicator shows new position
- Video frame updates as they drag
- Smooth preview of frames

**On Release**:
- Playback jumps to new position
- If in middle of transition, snaps to nearest clip boundary
- Playback continues from new position
- Controls stay visible briefly

### Seeking to Specific Clip

**User Action**: Taps Previous/Next button

**User Sees**:
- Immediate jump to clip start
- Clip counter updates
- Playback continues
- Transition plays if enabled

### Seeking to Start

**User Action**: Drags progress bar to beginning

**User Sees**:
- Playback jumps to start (0:00)
- First clip starts playing
- All clips available to play again

### Seeking to End

**User Action**: Drags progress bar to end

**User Sees**:
- Playback jumps to last frame
- Final clip displayed
- Playback finished state
- Can drag back to replay

---

## Play Again / Replay

### After Tape Finishes

**User Experience**:
- Playback stops at end
- Last frame remains visible
- Controls appear automatically
- Play button available to restart

**User Action**: Taps play button

**What Happens**:
- Playback starts from beginning (0:00)
- First clip plays
- Full tape plays again
- No need to reload (composition already built)

### Manual Replay

**User Action**: Drags progress bar to start OR taps previous multiple times

**What Happens**:
- Immediate jump to start
- Playback continues automatically
- Full tape plays from beginning

### Replaying Specific Section

**User Action**: Drags to middle, watches, drags back to same spot

**What Happens**:
- Seeks instantly to new position
- Playback continues smoothly
- No reloading needed
- Can repeat any section easily

---

## Skipping Clips

### Skip During Playback

**User Action**: Taps Next button while playing

**User Sees**:
- Immediate jump to next clip
- Clip counter updates (e.g., "3 of 12" → "4 of 12")
- Playback continues
- Transition plays if enabled

### Skip to Previous

**User Action**: Taps Previous button while playing

**User Sees**:
- If at start of clip: jumps to previous clip start
- If in middle of clip: jumps to current clip start
- Clip counter updates
- Playback continues

### Rapid Skipping

**User Action**: Rapidly taps Next/Previous

**User Sees**:
- Each tap jumps immediately
- Clip counter updates each time
- No delay or lag
- Smooth transitions still play

**Performance**: Handles rapid skipping without issues (no composition rebuilding)

---

## Error Scenarios

### Photos Access Denied

**User Sees**:
- Error overlay appears
- Message: "Photos access is required to play this tape"
- Button: "Open Settings"
- Close button available

**User Action**: Taps "Open Settings"

**What Happens**:
- Opens iOS Settings app to Photos permission
- User can grant access
- Returns to app, can retry playback

### Some Clips Unavailable

**User Sees**:
- Loading completes successfully
- Toast notification: "2 clips skipped (unavailable)"
- Playback starts with available clips
- Clip counter reflects actual count (e.g., "1 of 10" instead of "1 of 12")

**Behavior**:
- Skipped clips are logged
- Playback continues smoothly
- No interruption to user experience

### Network Timeout

**User Sees**:
- Loading takes longer than expected
- Eventually: "Some clips timed out"
- Playback starts with available clips
- Retry option available

### All Clips Failed

**User Sees**:
- Error overlay appears
- Message: "Unable to load any clips for this tape"
- Close button available
- Option to try again

---

## Loading States (Detailed)

### Initial Load

**Visual**:
```
┌─────────────────────────────┐
│                             │
│                             │
│       [Spinner]             │
│    "Loading tape..."        │
│                             │
│                             │
└─────────────────────────────┘
```

**Behavior**:
- Appears immediately when player opens
- Stays visible until composition ready
- Cannot be dismissed (must wait or close player)

### Progress Indication

**For Long Loads** (optional enhancement):
- Progress bar appears under "Loading tape..."
- Shows: "Loading 8 of 12 clips..."
- Updates as each clip resolves
- Gives user sense of progress

### Completion

**Visual**:
- Loading overlay fades out
- Video appears
- Playback starts automatically
- Controls briefly visible, then fade

---

## Full-Screen Experience

### Immersive Mode

**When Controls Hidden**:
- Full-screen black background
- Video fills entire screen
- No UI elements visible
- Maximum immersion

**When Controls Visible**:
- Header at top (close, counter)
- Progress bar at bottom
- Control buttons centered at bottom
- Semi-transparent overlays (glass effect)

### Orientation Support

**Portrait Tapes**:
- Video fills screen vertically
- Black bars on sides (if device is landscape)
- Optimal viewing experience

**Landscape Tapes**:
- Video fills screen horizontally
- Black bars on top/bottom (if device is portrait)
- Optimal viewing experience

---

## AirPlay / Casting

### Discovering Devices

**User Action**: Taps AirPlay button

**User Sees**:
- Native iOS AirPlay picker appears
- Lists available devices (Apple TV, AirPlay speakers, etc.)
- Can select device

### Streaming to Device

**What Happens**:
- Video streams to selected device
- Phone screen shows controls
- Playback controls work on phone
- Video plays on external device

**Experience**:
- Smooth streaming
- Transitions work on external device
- Audio routes to device
- Full functionality maintained

---

## Accessibility

### VoiceOver

**User Experience**:
- Can navigate all controls with VoiceOver
- Labels read aloud: "Play button", "Previous clip", etc.
- State announcements: "Playing", "Paused", "Clip 3 of 12"
- Progress bar announces current time

### Reduce Motion

**User Experience**:
- Slide transitions replaced with crossfades
- Ken Burns effect reduced or disabled
- Smooth but less motion-heavy experience

### Dynamic Type

**User Experience**:
- Controls scale with text size preference
- Loading messages use system fonts
- Readable at all text sizes

---

## Performance Characteristics

### Fast Tapes (All Local)

**User Experience**:
- Loads in < 1 second
- Instant playback start
- Smooth 60fps playback
- No stalling
- Perfect transitions

### Moderate Tapes (Mixed Local/iCloud)

**User Experience**:
- Loads in 1-3 seconds
- Smooth playback once started
- Occasional brief stalls if network slow
- Recovers quickly

### Large Tapes (30+ clips)

**User Experience**:
- Loads in 2-5 seconds (all clips in parallel)
- Smooth playback throughout
- Memory efficient
- No performance degradation

---

## User Flow Summary

### Typical Session

1. **Tap Play** → Loading appears immediately
2. **Wait 1-3 seconds** → All clips load in parallel
3. **Loading disappears** → Playback starts automatically
4. **Watch tape** → Smooth playback with transitions
5. **Controls auto-hide** → Immersive full-screen
6. **Tap screen** → Controls appear
7. **Interact** (scrub, skip, pause/play) → Instant response
8. **Tape finishes** → Last frame visible, controls appear
9. **Tap close** → Returns to tape list

### Scenarios Covered

✅ **Video-only tapes**: Smooth video playback
✅ **Image-only tapes**: Ken Burns with transitions
✅ **Mixed tapes**: Seamless video-to-image transitions
✅ **iCloud tapes**: Loading then smooth playback
✅ **Different transitions**: All render seamlessly
✅ **Seeking**: Instant, accurate, smooth
✅ **Skipping**: Immediate clip navigation
✅ **Replay**: Can play again instantly
✅ **Errors**: Clear messages, graceful handling
✅ **Accessibility**: Full VoiceOver and Reduce Motion support

---

## Key Differentiators

### What Makes This Experience Special

1. **Fast Loading**: Parallel asset loading, ready in seconds
2. **Seamless Transitions**: Transitions rendered in composition, no glitches
3. **Smooth Playback**: Single composition, no mid-play swaps
4. **Instant Controls**: All interactions are immediate (no lag)
5. **Bulletproof**: Handles all error scenarios gracefully
6. **Full-Screen Immersive**: Apple HIG compliant, Memories-like experience
7. **Reliable**: Never gets stuck, always recoverable

---

**Document Version**: 1.0  
**Created**: Complete user experience description  
**Status**: Ready for implementation reference

