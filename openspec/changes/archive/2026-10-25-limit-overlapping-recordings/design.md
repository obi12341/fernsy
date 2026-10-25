# Design

## Context

`Recorder` (`Fernsy/Recording/Recorder.swift`) stores each recording with the show's
`start`/`end` and `padBefore`/`padAfter`. The window `recordStart…recordEnd` is computed from
those four values. A 5-second `tick` starts a recording 20 s (`tuneAhead`) before
`recordStart` and finishes it once `recordEnd` has passed.

`TunerPool` (in `LiveTuner.swift`) allows `limit` channels at once, taken from
`account.maxConnections` or `IPTV_MAXCONN`. Owners of the same channel share one tuner.
`blockers(for:as:)` lists the channels that would have to give way.

Planning today:
- `schedule` only checks padded windows on other channels, and only with
  `overlapping.count >= limit`. It counts recordings, not channels, and ignores whether they
  overlap each other.
- The result is a warning. The plan is still made.

At start time:
- `resolveConflicts` asks "end the other recording and record" and defaults to yes after
  60 s.
- For back-to-back shows on different channels with a single stream, the later recording's
  pre-roll (plus `tuneAhead`) cuts the earlier show's real end.

Decision from `configurable-recording-padding`: more overlaps from 10/10 padding were left to
the prompt. This change reopens that decision for the reason above: the prompt costs the end
of a show the user planned.

## Goals / Non-Goals

**Goals:**
- No plan whose shows can't all be recorded within the stream limit.
- Padding never costs another planned show any of its own time.
- After-padding takes precedence over before-padding.
- Back-to-back handover without a prompt.
- Windows stay correct when plans, settings or the limit change.

**Non-Goals:**
- Planning around the player's connection. The player is transient; the existing prompt
  stays.
- Connections used by other devices.
- Splitting a recording or moving it to another channel.

## Decisions

### 1. Streams are counted per channel over time

The plan is checked with a sweep over the start and end times of the relevant intervals:
- show times, when checking for a real overlap;
- windows, when shortening padding.

At each moment, the number of distinct channels may not exceed `limit`. Recordings on the
same channel count once, because `TunerPool` shares the tuner.

This lives in a small pure type `RecordingPlan` in `Fernsy/Recording/RecordingPlan.swift`,
so it can be self-tested (`IPTV_PLANTEST=1`, like `IPTV_NAMETEST`).

Rejected: counting overlapping recordings, as today. That misjudges same-channel pairs, and
recordings that overlap the new one but not each other.

### 2. Real overlaps are refused when planning

`schedule` and `recordNow` return a result instead of an optional warning: either
`.planned(notice:)` or `.refused(message:)`. They refuse when the new show's own time,
together with the show times of scheduled and running recordings, exceeds the limit at any
moment. The message names the recordings in the way and the limit.

The callers show it with `Prompt.inform`, titled "Aufnahme nicht möglich". The callers are
the guide, the detail pane and its context menu, the player's R key and record button, and
search/Recordings via `RecordingsView`. A recording from the player without program data
uses its two hours as the show time.

Rejected:
- **Keep planning and ask at start, as today:** it loses show time, which is the problem.
- **Offer to replace the other recording in the refusal:** the user can remove it and plan
  again. One more dialog path is not worth it.

### 3. Padding is shortened by a fixed order

`RecordingPlan.windows(for:limit:now:)` computes each active recording's window. It starts
from the show times, which fit by decision 2. Then it widens in two passes:

1. **After-padding, by show end in ascending order.** Each end moves out up to
   `end + padAfter`, as far as the channel count stays within the limit.
2. **Before-padding, by show start in ascending order.** Each start moves back up to
   `start - padBefore`, by the same rule.

Because the show times are placed first, padding can never reach into another recording's
show. Because after-padding is placed first, it wins over the next show's before-padding.
This matches the user's rule: the start of a show must always be kept, and before-padding
can be given up sooner than after-padding.

Running recordings keep their actual start. Only their end can still be shortened, and never
to before now. Found during implementation: the same holds for a scheduled recording whose
window has already begun (waiting for a handover). Otherwise, when the first recording finishes,
the recalculation would hand the second one its full before-padding afterwards, and the
Recordings list would show a start it never recorded from.

Rejected: splitting the gap in half. The user prefers keeping after-padding, because shows
overrun more often than they start early.

### 4. The shortened window is stored, the configured padding stays

`Recording` gets `clipBefore`/`clipAfter`: seconds taken off the padding, persisted and
defaulting to 0 (`decodeIfPresent` for old lists). `recordStart` and `recordEnd` include
them, so `tick`, `begin`, the Recordings list and the menu bar automatically use the
shortened window.

`Recorder.rebalance()` recalculates the clips of scheduled and running recordings after:
- `schedule`, `recordNow`, `stop`, `delete` and `finish`;
- `applyPadding`, and `activate` (load);
- a change of the limit (`AppModel.updateConnectionLimit` calls it).

The padding a user set stays in `padBefore`/`padAfter`, so a removed neighbour gives the
full padding back.

Rejected: writing the shortened padding into `padBefore`/`padAfter` directly. The original
value would be lost, and it could not be restored.

### 5. The planning notice names what was shortened

After `rebalance()`, `schedule` compares each recording's clips with those before the plan.
The notice lists every recording whose window got shorter, including neighbours, for
example: "Vorlauf von „B“ verkürzt auf 0 Min." or "Nachlauf von „A“ verkürzt auf 4 Min.".
No notice appears when nothing got shorter.

### 6. Handover instead of the prompt

In `begin`, before `resolveConflicts`, Fernsy checks the blockers. If every one of them is a
recording whose window ends at or before this recording's `recordStart`, it waits until
then. It finishes those recordings exactly at their end (not on the next 5-second `tick`),
then acquires the tuner.

The new connection needs a moment, so the first seconds of the handover may be missing
before the first keyframe. This is accepted; the buffer starts writing as soon as data
arrives (`entry(atOrBeforeWall:)` falls back to the first entry).

Everything else still goes through the prompt:
- conflicts with the player;
- old plans with real overlaps;
- plans broken by a lower limit.

### 7. The stream limit is saved per account

`AppModel` writes the reported `maxConnections` to `connections.json` in the account folder
(`Application Support/Fernsy/<accountKey>/`, next to the catalog cache and
`recordings.json`). It reads the file when an account becomes active, before the first
`tick`, and uses it until `account()` answers.

`refresh(client:dir:)` asks `account()` again with every catalog refresh (at most every
5 minutes), so a changed package arrives without signing in again. A failed request keeps
the last value. Only an account without a saved value falls back to 1. Like the catalog
cache, the file stays when the user signs out. Signing in again asks the provider anyway.

Rejected:
- **UserDefaults:** it is not per account. Test runs with the demo account would also write
  into the user's defaults.
- **Waiting for the provider before the first recording:** recordings must also start when
  the provider is briefly unreachable at app start.

## Risks / Trade-offs

- **[A gap of a few seconds at a handover]** → It is accepted, because it happens at the
  show boundary, not inside a show. With more streams than recordings there is no handover.
- **[The provider reports a wrong limit]** → Fernsy follows what the provider reports; the
  prompt at start still catches a refused connection. Only a never-reported limit defaults
  to 1.
- **[Old lists with real overlaps]** → `rebalance` reduces their padding to 0. The prompt at
  start remains for them.
- **[The player is not planned for]** → It is unchanged. It is covered by the existing
  prompt.
