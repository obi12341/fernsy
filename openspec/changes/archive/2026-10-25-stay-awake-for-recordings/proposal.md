# Proposal

## Why

Fernsy keeps the Mac from idle sleep only during a recording and in the hour before it. A Mac
that falls asleep earlier, for example in the evening for a recording at night, misses the
recording, because a sandboxed app cannot wake the Mac. Users should decide how far ahead a
scheduled recording keeps the Mac awake.

## What Changes

- New setting in Settings › Aufnahmen: "Mac wach halten" with the choices "Aus", 1, 3, 6, 12
  and 24 hours before a recording and "Immer, solange eine Aufnahme geplant ist"; default 6
  hours (today it is a fixed hour).
- "Aus" switches the whole feature off: Fernsy never keeps the Mac awake, not even during a
  recording, and the footnote warns that a recording stops when the Mac sleeps.
- While a scheduled recording starts within that time, or a recording runs, Fernsy prevents
  idle sleep. When none does (last recording finished, deleted or far enough away), the Mac
  may sleep again as usual.
- The footnote in Settings explains what this cannot prevent: closing the lid on battery, or
  choosing Sleep in the Apple menu.
- Debug switch `IPTV_AWAKEHOURS=<hours|0|off>` (0 = always) sets the value in memory for one run.

Out of scope:
- Waking a sleeping Mac for a recording (needs a privileged scheduled power event, not
  available in the sandbox).
- Keeping the display on, or keeping the Mac awake for live playback (playback already does
  this itself).
- Launching Fernsy at login (separate change `launch-at-login`).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `recordings`: "Recordings run while the app runs" gets the configurable keep-awake time
  instead of the fixed hour.

## Impact

- `Fernsy/Recording/Recorder.swift` (`updateActivity()` reads the setting; key and choices).
- `Fernsy/Views/LoginView.swift` (`RecordingSettings`: picker and footnote; the menu bar
  footnote mentions it).
- `Fernsy/Localizable.xcstrings`, `DEVELOPMENT.md` (debug switch).
