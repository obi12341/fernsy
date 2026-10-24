# Tasks

## 1. Grid

- [x] 1.1 `GuideCell`: past/running/upcoming states with the elapsed fill, recording frames (double for scheduled) and the red "● Aufnahme läuft/Geplant · time" line. Verify: demo screenshot with `IPTV_SELECT`-free run plus `IPTV_TESTRECORD` (running) and a scheduled show (`IPTV_TESTSCHEDULE` in the guide, design §4 hook).
- [x] 1.2 Hatched no-data bar with the two-line text, double-click plays. Verify: a demo channel without EPG, or `IPTV_TESTNOEPG=<id>` (debug: empty listings for that channel), screenshot.
- [x] 1.3 Ruler now pill, channel column 188 pt. Verify: screenshot.

## 2. Navigation

- [x] 2.1 Collapse the category column in guide mode (not in Edit mode); toolbar category menu sharing the selection. Verify: screenshot of the guide without the column and with the menu title.
- [x] 2.2 Day stepper (today + 3), time jump menu, red "Jetzt". Verify: `IPTV_GUIDEDAY=1 IPTV_GUIDETIME=20:15` (debug) shows tomorrow at 20:15 (screenshot).

## 3. Detail bar

- [x] 3.1 Detail bar layout (logo, caption with relative time, title, description, Aufnehmen/Einschalten column, ✕) and R as a shortcut for the selected show. Verify: screenshot with a selected show (`IPTV_GUIDESELECT=<channel id>:<n-th upcoming>` debug).

## 4. Localization and verification

- [x] 4.1 Strings (de + en), no stale keys, README switches. Verify: build.
- [x] 4.2 Debug/Release builds. `openspec validate redesign-program-guide --strict` and `openspec validate --specs --strict`. Screenshots dark and light.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
