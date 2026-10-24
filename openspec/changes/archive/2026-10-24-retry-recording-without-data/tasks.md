# Tasks

## 1. Tuner keeps trying for recordings

- [x] 1.1 `LiveTuner.handle`: when `keepTrying` is set, retry a non-retryable failure (except `writer.isFailed` and `PlayerError.unsupported`) after 30 s, in state `.reconnecting`. The player-only path stays unchanged. Verify: debug log `[tuner …] failed: … (retry: false)` followed by a reconnect 30 s later, while a recording owns the tuner.

## 2. Recorder waits for data until the window ends

- [x] 2.1 `Recorder.begin`: after the conflict check, set the status to `.recording` (fileName nil) and wait while the entry is `.recording` without a copier and `Date() < recordEnd`. Create the copier on the first buffer entry and only if the entry is still `.recording`. Otherwise release the tuner. Verify: build succeeds, and the debug log shows "started …" only once data exists.
- [x] 2.2 `Recorder.finish` without a copier: mark the entry `.failed` with "Keine Daten vom Sender" (bytes nil) and release the tuner. Verify: stopping a waiting recording shows it as failed with that text.
- [x] 2.3 `RecordingRow`: while `status == .recording && fileName == nil`, show "Wartet auf den Sender …" as the detail and no progress-based play button. Verify in the Recordings section during the run in 4.2.

## 3. Debug switch

- [x] 3.1 `IPTV_TESTNODATA=<offline|silent>:<s>` (DEBUG, tuner sessions only): for that many seconds after the first tuner connection, `openInput` throws `PlayerError.offline` or, for `silent`, waits 8 s and throws a timeout. Document it in README next to `IPTV_TESTRECORD`. Verify: the debug log shows the simulated failures only within that time.

## 4. Localization and verification

- [x] 4.1 Add "Wartet auf den Sender …" (EN "Waiting for the channel…") to `Localizable.xcstrings` via `xcstringstool sync`, in the repo's JSON format. Verify: no stale keys, and the build has no missing-translation warnings for it.
- [x] 4.2 Demo server, `IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev` demo/demo, `FERNSY_NO_KEYCHAIN=1`, `IPTV_TESTNODATA=silent:90`, `IPTV_TESTRECORD=<channel>:30:180`. Expected: the list shows the waiting note, the recording starts writing after about 90 s, and it ends as recorded. The file plays (ffprobe shows video and audio).
- [x] 4.3 Same with `IPTV_TESTNODATA=offline:90`. Expected: the tuner retries every 30 s, and the recording starts once the switch expires.
- [x] 4.4 `IPTV_TESTNODATA=offline:600` with `IPTV_TESTRECORD=<channel>:10:60`. Expected: the recording ends after its window as failed with "Keine Daten vom Sender", and no file is left behind.
- [x] 4.5 Player alone with `IPTV_TESTNODATA=offline:600` (no recording). Expected: the player shows the offline message after the usual attempts, with no endless retries.
- [x] 4.6 `IPTV_MAXCONN=1`: a waiting recording holds the slot. Switching the player to another channel asks before stopping it. Verify with the prompt shown.
- [x] 4.7 `openspec validate --all --strict` passes.

## Workflow follow-up

- Manual check by the user with a real scheduled show, if they want one.
- `/opsx:archive`, then merge into main and push, only after the user agrees.
