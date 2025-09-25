# TAPES — MVP QA Smoke-Test Checklist (v18)

> Step-by-step tester script with checkboxes and Pass/Fail column.

## 1) App Launch & New Tape
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 1.1 | Launch the app | Home shows empty Tape or last opened Tape. | [ ] |  |
| 1.2 | Create a new Tape | New timeline opens with start **+** and end **+**; record button centered. | [ ] |  |
| 1.3 | Verify snapping math | Carousel snaps so a thumbnail/**+** sits on each side of the fixed center button. | [ ] |  |

## 2) Insert Clips
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 2.1 | Record a short clip | Clip inserts at the **center** slot. | [ ] |  |
| 2.2 | Add from device | Clip inserts at the **center** slot. | [ ] |  |
| 2.3 | Insert at start | Clip appears at **index 0** via the start **+**. | [ ] |  |

## 3) Edit Sheet
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 3.1 | Tap a clip | Edit sheet shows Trim / Rotate / Fit-Fill / Share / Remove. | [ ] |  |
| 3.2 | Trim | Saves new trimmed asset and replaces in Tape. | [ ] |  |
| 3.3 | Remove | Confirmation dialog; if Tape empty → only **start +** remains. | [ ] |  |

## 4) Settings (Tape-Level)
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 4.1 | Orientation | Switches to 9:16 or 16:9 canvas. | [ ] |  |
| 4.2 | Aspect Fit | Whole video, letter/pillar-boxing. | [ ] |  |
| 4.3 | Aspect Fill | Crops to fill. | [ ] |  |
| 4.4 | Transition None | Hard cuts preview + export. | [ ] |  |
| 4.5 | Transition Crossfade | Fades preview + export. | [ ] |  |
| 4.6 | Slide L→R / R→L | Slides preview + export (iOS AVF, Android FFmpeg). | [ ] |  |
| 4.7 | Randomise | Deterministic per Tape; **0.5s clamp**. | [ ] |  |

## 5) Preview
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 5.1 | ▶️ → Preview | Plays with correct transitions and Fit/Fill/Rotation. | [ ] |  |
| 5.2 | Restart | Seeks to 0; plays. | [ ] |  |

## 6) Export
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 6.1 | ▶️ → Merge & Save | Progress UI appears. | [ ] |  |
| 6.2 | iOS | Saves to **Photos › Tapes** with video+audio crossfades. | [ ] |  |
| 6.3 | Android | Saves to **Movies/Tapes** with xfade/acrossfade & 1080p canvas. | [ ] |  |
| 6.4 | Error | Alerts/Toasts on failure. | [ ] |  |

## 7) Casting UI
| Step | Action | Expected Result | Done | Result |
|---|---|---|---|---|
| 7.1 | No devices | Cast button hidden. | [ ] |  |
| 7.2 | Device available (iOS) | AirPlay button appears; system picker opens. | [ ] |  |
| 7.3 | Device available (Android) | Cast button appears; toast “not implemented”. | [ ] |  |

## Sign-off
Tester: ____________   Date: ____________   Build: ____________
