# Tasks

## 1. Content clock

- [x] 1.1 Give `HTTPByteSource` a content-clock closure (`() -> Double?`) and a sample ring of `(wall, content)` taken in `checkStall()` before locking `cond`, cleared when a live connection is answered; wire it from `LiveTuner` through the tuner `PlaybackSession` to the writer's newest clock-stream time (`TimeshiftWriter.contentTime`, see design A). Verify: debug build compiles with 0 warnings, and a `debugLog` of the samples on the demo server shows content time advancing about 1 s per second.

## 2. Slow rule and edge choice

- [x] 2.1 Add the slow rule to `checkStall()`: connection ≥ 20 s old, content in the last 15 s < 9 s → `liveReconnect` with the localized reason "zu langsam: %.0f s Inhalt in 15 s"; set `lastSlowAt` on firing and on any full window below the threshold. Verify with 5.1.
- [x] 2.2 In `liveReconnect`, set `avoidEdge` when the reason is slowness or `lastSlowAt` is under 60 s old, and make that first attempt go to the load balancer without backoff. Verify with 5.1 and 5.2 (log shows "(load balancer)").
- [x] 2.3 Log "connected (HTTP <status>) via <host>" (info, network) when a live connection's first response arrives. Verify: demo-server run log shows the line once at channel start, without a path or credentials.
- [x] 2.4 Add the new reason string to `Localizable.xcstrings` (de + en) via `xcstringstool sync`. Verify: the string catalog has both languages and the build has no missing-localization warning.
- [x] 2.5 Repeat rule per design I: a slow connection within 2 minutes after a switch for slowness doubles the window (30 s, 60 s; 60 % needed) instead of switching; back to 15 s after 5 minutes without a slow window. Verify: demo-server run with `IPTV_TESTNET=trickle:20 IPTV_TRICKLEMORE=all` logs "judging over 30 s" and "60 s" and then switches about once a minute, playback continues (MCP `playback_diagnostics`).
- [x] 2.6 Log line per live connection per design J (release builds too). Verify: a normal demo-server run logs "connection ran …, lowest 15 s window … of content, longest pause between data … s" when the server closes the connection; no host or path in it.

## 3. Telling the user

- [x] 3.1 Publish the tuner's connection health (`ok`, `slow`, `silent`, `reconnecting` with target) from `LiveTuner` through `PlayerEngine`, and add an `NWPathMonitor`-backed "network available" flag to `AppModel`. Verify: a `debugLog` on health changes during the trickle run (5.1) shows ok → slow → reconnecting(load balancer) → ok.
- [x] 3.2 Status card in `PlayerScreen` per design F (after 1 s of buffering, no-internet before provider, plain spinner while healthy). Verify: window screenshot of the debug app during the trickle run shows "Der Sender kommt zu langsam vom Anbieter"; with `IPTV_TESTNOPATH=1` (DEBUG, forces the path to unsatisfied) and `IPTV_TESTNET=stall:20` it shows "Keine Internetverbindung".
- [x] 3.3 One-shot note after a load-balancer reconnect that follows `slow`/`silent` and then 5 s of real-time content (design G). Verify: window screenshot during the trickle run shows "Ein anderer Server des Anbieters liefert wieder flüssig." after the reconnect, and none after `IPTV_TESTNET=drop:20`.
- [x] 3.4 Recording gaps per design H: optional `gaps` on `Recording`, sampling in the recorder, row text in `RecordingsView`. Verify: decoding a copy of the demo account's existing `recordings.json` (backed up first) still works, and the run in 5.2 lists a gap with "Anbieter hat zu wenig geliefert" while running and after it finished.
- [x] 3.5 Strings for cards, note and gap texts in `Localizable.xcstrings` (de + en). Verify: catalog has both languages, no missing-localization warning.

## 4. Debug switch

- [x] 4.1 Add `trickle:<s>` to `IPTV_TESTNET` (DEBUG only) with the rate from `IPTV_TRICKLEKBIT` (default 300), throttling the current connection by suspend/resume until the next reconnect; document it in DEVELOPMENT.md next to the other `IPTV_TESTNET` actions. Verify: demo-server run with `IPTV_TESTNET=trickle:20` shows the info overlay's bitrate dropping to about 0.3 Mbit/s.

## 5. Verification

- [x] 5.1 Demo-server run (base debug env, `IPTV_TESTNET=trickle:30`), watching live: within 20 s of the trickle the log shows "live reconnect … zu langsam" and "reconnected … (load balancer)", and playback continues. Check the player state via MCP `playback_diagnostics` on the debug port.
- [x] 5.2 Demo-server run with `IPTV_TESTRECORD=<ch>:5:120:0:0` and `IPTV_TESTNET=trickle:30`, without a player window: the recording tuner reconnects the same way, and the finished `.ts` plays (ffprobe), and the recording lists its gap if the trickle lost 10 s or more (use `IPTV_TRICKLEKBIT=100` so it does).
- [x] 5.3 Regression on the demo server: plain `IPTV_TESTNET=drop:20` still reconnects via "(same edge)", and 3 minutes of normal live playback produce no slow reconnect, no provider card and no gap.
- [x] 5.4 `openspec validate --all --strict` exits 0, Debug and Release builds have 0 warnings.

## Workflow follow-up

- Commit with Release-Note-de/-en trailers (user-visible: slow streams recover by themselves, the player and recordings say when the provider is the cause).
- Archive the change, merge `change/slow-live-stream-reconnect` into main, push and build a nightly only with the user's agreement.
