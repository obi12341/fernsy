# Tasks

## 1. Test switch and baseline

- [x] 1.1 Add the DEBUG override `IPTV_TESTWATER=<high KB>:<low KB>[:<timeout s>]` for `highWater`/`lowWater` and the non-live request timeout in `HTTPByteSource`, plus detail-level log lines when a download is held (`download held at <offset>`) and resumed (`download resumed after <s> s`). Document the switch next to `IPTV_TESTNET` in `DEVELOPMENT.md`. Verify with a debug build.
- [x] 1.2 Reproduce the bug before the fix. Run Fernsy Dev on the demo server (`scripts/dev-run.sh IPTV_AUTOPLAY=movie:<demo id> IPTV_TESTWATER=<high>:<low>`), with marks and a short timeout chosen so that a hold outlasts the timeout at the demo film's bitrate (52 s, 2.24 Mbit/s), e.g. `IPTV_TESTWATER=8192:256:6`. Verify that within the film the log shows a hold longer than the timeout followed by `download interrupted … (The request timed out.), continuing`.

## 2. Short holds

- [x] 2.1 On every hold, schedule a keep-alive after half the request timeout (15 s normally) that resumes the same hold (generation counter) while less than 2 × `highWater` is buffered ahead; keep the `lowWater` resume. Verify that the debug and release builds compile.
- [x] 2.2 Run the demo proxy (catalog from the demo server, films redirected to the demo's `live.ts`; `IPTV_SERVER=http://127.0.0.1:8765 IPTV_AUTOPLAY=movie:500`) with the fix for about 2 minutes. Verify that the log shows `download kept alive` about every 15 s, also in the start phase without reads, no `download interrupted`, and `rebuffers=0` in the stats lines.
- [x] 2.3 Check that a pause is unchanged. Run the same setup and pause with `IPTV_TESTPAUSE=<at>:<s>` for longer than the test timeout, then resume. Verify that keep-alives stop at the ceiling (2 × `highWater`) during the pause, and that after resuming the film plays on: through the existing `continuing` path if the connection timed out, without an error.
- [x] 2.4 Update the code comments at `highWater`/`lowWater` to state the keep-alive and why (the 30 s request timeout runs while suspended). Verify that `openspec validate --all --strict` passes.

## 3. Integration

- [x] 3.1 Run a normal demo film without `IPTV_TESTWATER` (the file is smaller than `highWater`, so no hold happens) and a demo live channel for about 60 s each. Verify in the log that both play without new warnings, and that live behaves as before (reconnect after ~75 s, no rebuffer).

## Workflow follow-up

- The user checks a low-bitrate archive on their own account in the installed app after a release or a Fernsy Dev run without the installed app open. The single-stream rule applies, so I never run that test myself while the user's Fernsy runs.
- Commit with Release-Note-de/-en trailers, archive the change, then merge into `main` and push once the user agrees.
