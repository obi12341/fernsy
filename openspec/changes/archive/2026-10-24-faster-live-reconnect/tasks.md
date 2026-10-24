# Tasks

## 1. Measurement

- [x] 1.1 `PlayerEngine`: stall start on `.buffering(true)` after `.started`; on `.buffering(false)` (or a new item), log `AppLog` player "stalled for X.X s" (info, warning from 3 s on). Verify: a demo run with `IPTV_TESTNET=stall:20` shows one stall entry with a plausible duration.

## 2. Reconnect rules

- [x] 2.1 `HTTPByteSource`: store `playbackAheadAt` in `reportPlaybackAhead`, and add rule B to `checkStall` (`idle > 2 && ahead < 1 && reportAge < 2`) with the reason text showing which rule fired. A fresh connection is exempt for its first 4 s. Verify: with `IPTV_LIVELEAD=1.5` and `IPTV_TESTNET=stall:30`, the reconnect is logged with "player nearly empty" about 2 s after data stopped, and does not chain.
- [x] 2.2 Rule C: a 403/401 response to an edge reconnect makes the next attempt go to the load balancer with delay 0. Other statuses keep the backoff. Verify with `IPTV_TESTNET=forbid:20,drop:20`: the log shows "HTTP 403" followed by a load balancer attempt without delay.
- [x] 2.3 Rule D: remember the host and time of the last successful reconnect. A new incident within 20 s on the same host starts at the load balancer. Verify with `IPTV_TESTNET=flaky:20`: the second incident's first attempt is logged as "load balancer".
- [x] 2.4 DEBUG hooks `forbid:<s>` and `flaky:<s>` in `IPTV_TESTNET`, documented in README. Verify: the debug log shows the simulated events.

## 3. Specs and verification

- [x] 3.1 Demo server run (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo, `FERNSY_NO_KEYCHAIN=1`, `IPTV_AUTOPLAY=live:101`) without test switches for 3 minutes. Expected: no reconnects and no stall entries. Rule B must not fire on normal delivery.
- [x] 3.2 Recording only (`IPTV_TESTRECORD=102:5:60`, no player) with `IPTV_TESTNET=stall:20`. Expected: the reconnect comes from the old 4 s rule, not rule B.
- [x] 3.3 Debug and release builds compile. `openspec validate --all --strict` passes.

## Workflow follow-up

- Optional: the user compares stall entries in their own log after a few days with the old pattern.
- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
