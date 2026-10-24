# Tasks

## 1. Panel and overlay

- [x] 1.1 `PlayerTimeline.swift`: `LiveTimeline` (buffer range, clock ticks, show boundaries and titles, live dot, drag/click seek, go live at the end, accessibility) and `FilmTimeline` (played/buffered, hover marker with time pill, drag/click seek). Verify: demo live screenshot shows the boundaries. A film screenshot shows the bar.
- [x] 1.2 `ControlPanel`: live first line (JETZT/DANACH), buttons per design §4 (behind pill with ZU LIVE / LIVE badge, record capsule, combined "Ton & UT" menu, round buttons), film ±60/±10, appearance-following glass. Verify: screenshots live (behind via `IPTV_TESTPAUSE`), at the live edge, and a film, in dark and light.
- [x] 1.3 `CaptionPill` and `RecordingPill`, plus the gradients. Verify: live screenshot with `IPTV_TESTRECORD` on the playing channel shows "Aufnahme · bis HH:MM".

## 2. States, banner, PiP

- [x] 2.1 State cards: loading with logo, reconnecting (with `reconnectAttempt` from the engine), failure (offline variant with Nächster Sender). Verify: `IPTV_TESTNODATA=offline:600` + `IPTV_AUTOPLAY=live:101` screenshot. Loading is visible in `IPTV_TESTSLOWSTART=5`.
- [x] 2.2 Zap banner redesign. Verify: `IPTV_TESTZAP=1` screenshot during the banner.
- [x] 2.3 PiP loading card with logo tile. Verify: `IPTV_TESTSWITCH` while `IPTV_TESTPIP` runs; PiP-region screenshot.

## 3. Localization and verification

- [x] 3.1 Strings (de + en), no stale keys. Verify: build.
- [x] 3.2 Debug/Release builds. `openspec validate redesign-player --strict` and `openspec validate --specs --strict`. Existing player switches still work (`IPTV_TESTPAUSE`, `IPTV_TESTGOLIVE`, `IPTV_TESTSEEK`).

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
