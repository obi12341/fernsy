# Tasks

## 1. Sinks and spike (checkpoint 1)

- [x] 1.1 Add `Fernsy/Player/RendererSinks.swift`: `VideoSink` and `AudioSink` with lock, `enqueue`, `flush` and (video) `flushRemovingImage`, plus the event forwarding. Verify: the debug build compiles.
- [x] 1.2 `PlayerEngine`: create the receivers instead of using `addRenderer`, and do load/stop flushes through the sinks. `PlaybackSession`: sinks instead of renderers, `enqueueImmediately` in both output loops without readiness polling; the tuner gets no sinks. Loading card and the PiP flush through the sink. Verify: debug and release builds without deprecation warnings in the player files.
- [x] 1.3 **Checkpoint 1** (demo server, only when the user's Fernsy is closed): a live channel and a film play with sound and lip sync; PiP in and out; the loading card on zapping. Screenshots of the player window, and the log. On failure: stop, report, and record the reason in design.md.

## 2. Recovery

- [x] 2.1 Handle the results: video flush-required → `recoverVideo()` (rate-limited, giving up after 3 attempts in 30 s with a status); decode failures → counter in the technical info and a rate-limited log; audio suggested flush → refill (replaces the notification). Consume the rendering events.
- [x] 2.2 Debug switches `IPTV_TESTFLUSHREQUIRED=<s>` and `IPTV_TESTDECODEFAIL=<n>`; README.
- [x] 2.3 Strings (de + en) for "Decodierfehler" and the give-up status; no stale keys.

## 3. Checkpoint 2

- [x] 3.1 On the demo server, check:
  - timeshift (pause, rewind, back to live);
  - reconnect (`IPTV_TESTNET`);
  - a recording played while still recording;
  - zapping with the last picture;
  - the Dolby Vision fallback, if the demo media contains it (otherwise note it);
  - `IPTV_TESTFLUSHREQUIRED` (the picture continues, the log shows recovery);
  - `IPTV_TESTDECODEFAIL` (the counter in the info overlay).

  Result: all passed. The demo media is H.264 only, so the Dolby Vision fallback moves to the Jellyfin test in 4.1. A recording played while recording starts at 7–9 fps for the first seconds; `main` does the same (6.7 fps), so this is not caused by the receivers.
- [x] 3.2 Compare the CPU load of the player before and after (`top -pid` over 60 s, live channel) to document that there is no regression.

  Result: channel 101, 60 s at 25 fps: `main` 11.2 %, this branch 10.9 %.

## 4. Checkpoint 3 and wrap-up

- [x] 4.1 A nightly from this branch is not possible (nightly = main). Build a signed test DMG for the user locally with the Apple Development identity (`build-dmg.sh`; its smoke test launches the app for a moment, so only while the user's Fernsy is closed). The user tests: Jellyfin direct and transcode (including a Dolby Vision title), sleep/wake, AirPods/output change, a long live session. Keep this task open until the user confirms.
- [x] 4.2 `openspec validate renderer-receiver-api --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- Only after checkpoint 3: `/opsx:archive`, merge and push with the user's consent. If a checkpoint fails: record the reason in design.md, leave the branch unmerged, and report to the user.
