# Tasks

## 1. Reproduce

- [x] 1.1 Reproduce on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUTOPLAY=live:101`) — not possible: the demo backlog is ~10 s, so even a throttled connection (tried `IPTV_TESTTHROTTLE` at 1024/400/250 KB/s, then removed) never got past the old 17 s threshold; the user's provider sends ~18 s. Lag is produced instead with `IPTV_TESTSTALL=<at s>:<s>` (playback clock held, live state untouched)

## 2. Catch-up baseline

- [x] 2.1 `lagBaseline` in `PlayerEngine` and `leaveLiveIfLagging` (never seeks): baseline tracked during the first 15 s after a live start, leave live when lag > `max(baseline, liveLead) + 12` for 4 s, reset by `goLive`; verify with the same demo run: no jump, buffer chart without a drop, badge "LIVE" (screenshot) — `IPTV_TESTSTALL=6:14` inside the window: absorbed, "LIVE" with 12.9 s on disk, no seek; the lag is measured as the lowest value of the last 6 s because providers deliver in segments (lag swings 7–12 s on the demo)
- [x] 2.2 Real lag leaves live without a jump: verify with `IPTV_TESTNET` (simulated stall) on the demo server that playback falling > 12 s further behind keeps playing and the badge shows the time behind (screenshot, no seek in the log); and that `IPTV_TESTGOLIVE` then goes to the real edge and shows "LIVE" — `IPTV_TESTSTALL=20:16`: left live at 21.4 s behind (settled 7.1 s), badge "TIMESHIFT −0:20", no seek; `IPTV_TESTGOLIVE=52` back to "LIVE"

## 3. Finish

- [x] 3.1 README (debug switch, live start behaviour); update the timeshift design note in this change
- [x] 3.2 Optional check on the user's provider only with the user's app closed (`pgrep -fl "MacOS/Fernsy"`) and their OK — done with the user's OK (app closed, keychain access allowed by the user): ProSieben HD settled 14.5 s behind the newest data, no jump, "LIVE" with ~14 s on disk, 0 rebuffers (screenshot)

## Workflow follow-up

- Archive after the user's review, then merge `change/live-start-without-jump` into `main` with the user's OK.
