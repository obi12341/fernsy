# Tasks

## 1. Data

- [x] 1.1 `AppModel`: store the duration with resume positions, mark watched within the last 90 s, add `resumeFraction(_:)` and `isWatched(_:)` (in memory for keychain-less test runs). Hook up the player's `saveResume` calls with duration. Verify: build, and the debug log shows a watched flag after `IPTV_TESTSEEK` near the end of a demo film.

## 2. Grid

- [x] 2.1 Segmented sort picker, and movie posters with resume progress. Verify: demo screenshot of the movie grid with a resumed film.

## 3. Details

- [x] 3.1 Collapse the category column on detail pages, and the backdrop under the toolbar. Verify: screenshot of a film detail (`IPTV_SCENE=movies:__all:movie:<id>`).
- [x] 3.2 Film detail: meta line with runtime as hours and minutes, Fortsetzen with position and remaining time, Details grid. Verify: same screenshot, plus light (`IPTV_APPEARANCE=light`).
- [x] 3.3 Series detail: Nächste Episode, and episode rows with progress, Gesehen, Als Nächstes. Verify: screenshot of a demo series (`IPTV_SCENE=series:__all:series:<id>`) after marking episode 1 watched (`IPTV_TESTWATCHED=episode.<id>`).

## 4. Localization and verification

- [x] 4.1 Strings (de + en), with no stale keys. README lists new switches. Verify: build.
- [x] 4.2 Debug/Release builds. `openspec validate redesign-movies-and-series --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
