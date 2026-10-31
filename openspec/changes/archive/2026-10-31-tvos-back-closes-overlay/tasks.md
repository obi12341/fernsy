# Tasks

## 1. Back closes the top layer first

- [x] 1.1 `VODPlayerScreen.onExitCommand`: track panel → close (as now); else countdown → `cancelNext()`; else overlay showing → hide it without `touch()`; else `model.stop()`. Log each step like the live player ("remote back in …") (design 1, 2)
- [x] 1.2 `RecordingPlayerScreen.onExitCommand`: overlay showing → hide it without `touch()`; else `model.stop()`

## 2. Tests

- [x] 2.1 Check the Apple TV UI tests (also `PlayerStatusUITests.testFilmLoadingAndPreviewSpinner`, found by the full run) that press Back to stop a film, episode or recording (`PlayerUITests.swift:60`, `RecordingsUITests.swift:31`, `JellyfinOverviewUITests.swift:58`, `StartUITests.swift:54` and others found by searching `press(.menu)` while a `player.state` exists) and make them wait for the overlay to hide or press Back twice
- [x] 2.2 New UI test on "Claude Apple TV" with the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_USER=demo`, `IPTV_PASS=demo`):
  - Film `movie:500` from the start: Back with the overlay showing hides it and the film keeps playing (`player.state` stays "playing"); a second Back stops it.
  - With the subtitle panel open, Back closes the panel first.
  - A recording made with `IPTV_TESTRECORD=101:0:20:0:0` and `IPTV_FRESHRECORDINGS=1`: the first Back hides the timeline, the second stops.
- [x] 2.3 The full Apple TV UI suite passes (`DEVICE_NAME="Claude Apple TV" scripts/tv-uitest.sh`), `scripts/test.sh` passes, `openspec validate --all --strict` passes
- [x] 2.4 On "Apple TV WZ" (Release build) with the user: Back during a film hides the overlay first, a second Back ends it Confirmed by the user on 2026-10-31.

## Workflow follow-up

- Archive on `change/tvos-back-closes-overlay`, merge into `main` and push with the user's
  consent. Release notes: DE "Zurück auf der Apple-TV-Fernbedienung blendet bei Filmen, Serien
  und Aufnahmen erst die Einblendung aus und beendet erst beim nächsten Druck." / EN "On Apple
  TV, Back in films, series and recordings first hides the overlay and ends playback only on
  the next press."
