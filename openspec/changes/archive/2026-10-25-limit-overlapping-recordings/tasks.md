# Tasks

## 1. Plan calculation

- [x] 1.1 Add `Fernsy/Recording/RecordingPlan.swift`:
  - a per-channel stream sweep;
  - a real-overlap check that returns the recordings in the way;
  - `windows(for:limit:now:)`, which places the after-padding pass before the before-padding pass, and keeps the actual start of running recordings.
- [x] 1.2 Add the self-test `IPTV_PLANTEST=1` with the spec examples:
  - back to back → 21:45/21:45;
  - a 6-minute gap → 21:51/21:51;
  - same channel → 21:55/21:35;
  - real overlap at limits 1, 2 and 3;
  - full padding at limit 2;
  - three channels at limit 2 (A until 21:50, B from 21:35, C from 21:50);
  - a running recording;
  - a lowered limit.

  Verify: a debug run logs all of them as passed.

## 2. Recorder

- [x] 2.1 Add `Recording.clipBefore`/`clipAfter` (persisted, `decodeIfPresent`). `recordStart` and `recordEnd` include them.
- [x] 2.2 Add `Recorder.rebalance()`. Call it after:
  - schedule, recordNow, stop, delete and finish;
  - applyPadding and activate;
  - `AppModel.updateConnectionLimit`.
- [x] 2.3 `schedule`/`recordNow` return `.planned(notice:)` or `.refused(message:)`. The refusal names the recordings in the way and the limit; the notice lists the shortened paddings, including neighbours. This replaces `overlapWarning`.
- [x] 2.4 Handover in `begin`. When every blocker is a recording ending at or before this `recordStart`, wait, finish those recordings exactly at their end, then acquire. Otherwise use `resolveConflicts` as before.

- [x] 2.5 Save the stream limit: `connections.json` in the account folder, written when `account` arrives, read when the account becomes active (before the recorder's first `tick`), and kept when the request fails. `refresh` asks `account()` with every catalog refresh. Verify:
  - a demo run writes 5;
  - a second run with `IPTV_TESTCATALOGFAIL=1`, which now also makes `account()` fail, uses 5 from the file;
  - the log shows the limit and its source (saved or provider).

## 3. UI

- [x] 3.1 Show the refusal ("Aufnahme nicht möglich") and the notice ("Aufnahme geplant") at every planning call site:
  - `GuideView`;
  - `ChannelDetailPane`;
  - `RecordingsView`;
  - `PlayerScreen` (R and the record button).
- [x] 3.2 Check that the Recordings list shows the shortened window. Verify:
  - Run the demo server with `IPTV_MAXCONN=1`, and `IPTV_TESTRECORD` extended to a comma-separated list, e.g. `101:120:120:1:1,102:240:120:1:1` (back to back on two channels).
  - Take a screenshot of the Recordings list showing the shortened windows.

## 4. Handover on the demo server

- [x] 4.1 Run the demo server with `IPTV_MAXCONN=1` and `IPTV_TESTRECORD=101:60:90:1:1,102:150:90:1:1`. Confirm:
  - A ends at B's show start;
  - B starts right after without a prompt (log);
  - both files play.
- [x] 4.2 Same channel: `IPTV_TESTRECORD=101:60:90:1:1,101:150:90:1:1` keeps both paddings (log of the windows).
- [x] 4.3 Refusal: with `IPTV_MAXCONN=1`, a third overlapping `IPTV_TESTRECORD` entry is refused (log). With `IPTV_MAXCONN=2` it is planned.
- [x] 4.4 Afterwards, clean up the demo account's `recordings.json` and move the test `.ts` files to the Trash.

## 5. Localization and verification

- [x] 5.1 Update strings (de + en) without stale keys, the README switches (`IPTV_PLANTEST`, the `IPTV_TESTRECORD` list), and the pitfalls in design.md if any come up.
- [x] 5.2 Debug and Release builds; `openspec validate limit-overlapping-recordings --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit and merge into main, only after the user agrees.
