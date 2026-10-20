# Design

## Context

Padding is stored per recording (`padBefore`/`padAfter` in seconds, copied from
UserDefaults `recording.padBefore`/`recording.padAfter` at scheduling time) in the
per-account `recordings.json`. Settings use two Pickers with fixed values; defaults are
registered in `Recorder.init` (2/10). Recordings started from the player without program
data are created with padding 0. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:** new defaults without overriding explicit choices; free values 0–60 min; scheduled
entries follow the settings.

**Non-Goals:** per-recording editing UI.

## Decisions

### Defaults through `register(defaults:)`
Change the registered defaults to 10/10. UserDefaults only stores a value once the user
changed it, so untouched installs get 10/10 and explicit choices survive without a
migration step.
- Rejected: a one-time migration that rewrites stored values – would also override users
  who deliberately chose 2 minutes.

### Mark which recordings follow the settings
Add `followsPaddingSettings: Bool` to `Recording` (decoded as `true` when missing, so
existing scheduled entries follow the new settings). It is `false` for recordings without
program data (record-now without EPG) and for explicit padding (`IPTV_TESTRECORD`).
When the settings change, `Recorder` rewrites the padding of entries with status
`scheduled` and `followsPaddingSettings`, saves, and runs its tick (a recording whose new
start lies in the past starts right away).
- Rejected: recomputing the window from the settings on every tick – running and finished
  recordings must keep their actual window, and the list must show what will happen.
- Rejected: storing no padding per recording at all – same reason.

### Settings control
Each padding is a Stepper (1-minute steps) with a number field, clamped to 0…60 in the
binding so typed values outside the range are corrected. `@AppStorage` keeps the keys;
`Recorder` observes `UserDefaults.didChangeNotification` (debounced) to re-apply padding.

### Showing the window
Recording rows keep the show time and add "Recording 20:05 – 21:55" when padding is not
zero (from `recordStart`/`recordEnd`).

## Risks / Trade-offs

- [More overlaps with 10/10 on single-stream accounts] → existing conflict prompt; the
  overlap warning at scheduling already mentions it.
- [Changing padding to a larger value right before a show] → start moves into the past →
  the recording starts immediately, as far as the timeshift buffer reaches back if the
  channel is already tuned (existing behavior of choosing the start offset).
