# Design

## Context

`Recorder.updateActivity()` holds one `ProcessInfo` activity (`.idleSystemSleepDisabled`,
`.suddenTerminationDisabled`) while a recording runs or a scheduled one starts within a fixed
3600 s (`recordStart`, i.e. including padding). It is re-evaluated on every scheduler tick and
whenever recordings change, so a moving window needs no extra timer. The choice of one hour was
made in add-timeshift-and-recordings; this change makes it a setting because users schedule
evening and night recordings far earlier than an hour ahead.

## Goals / Non-Goals

**Goals:**
- One setting, read where the decision is made; the existing activity mechanism stays.

**Non-Goals:**
- Waking the Mac, display assertions, per-recording choices.

## Decisions

- **Setting as hours in `UserDefaults`** (`Recorder.keepAwakeHoursKey`, Int, default 6, 0 =
  always, -1 = off), shown as a `Picker` with "Aus", 1, 3, 6, 12, 24 h and "Immer, solange eine
  Aufnahme geplant ist". `RecordingSettings` uses `@AppStorage` like the padding fields; `Recorder` reads
  `UserDefaults` in `updateActivity()` and the settings change triggers `updateActivity()`
  (observing `UserDefaults.didChangeNotification` or a call from the view).
  Rejected: a free number field (invites odd values, the picker covers the useful range).
- **"Aus" switches everything off, including during a recording**, at the user's request: some
  users manage sleep themselves (power settings, Amphetamine, a Mac that never sleeps) and do
  not want an app holding an assertion. The footnote for "Aus" warns that a recording stops when
  the Mac sleeps. Rejected: "off" meaning "only during recordings" (that is close to the 1 h
  choice and would not let users switch the feature off as asked).
- **Keep `ProcessInfo.beginActivity(.idleSystemSleepDisabled)`.** It maps to a
  PreventUserIdleSystemSleep assertion, works in the sandbox and is released automatically if
  Fernsy quits or crashes. Rejected: `IOPMAssertionCreateWithName` directly (same effect, more
  code) and `IOPMSchedulePowerEvent` wake-ups (needs root; not possible from the sandbox).
- **The activity reason names the recording**, e.g. "Recording scheduled: <title> at 22:15",
  so `pmset -g assertions` tells the user why the Mac stays awake. The reason is updated when the
  nearest recording changes (end and begin a new activity).
- **Default 6 hours** as asked; existing users get 6 h instead of 1 h after the update, which
  only keeps the Mac awake longer.

## Risks / Trade-offs

- [A laptop on battery stays awake for hours] → the footnote says so; the user picks a shorter
  time; closing the lid on battery still sleeps.
- ["Always" with a recording scheduled days ahead keeps the Mac awake for days] → that is the
  explicit choice; the footnote names it.
- [A user picks "Aus" and loses a recording to sleep] → explicit choice; the footnote says it,
  and the default stays 6 hours.
