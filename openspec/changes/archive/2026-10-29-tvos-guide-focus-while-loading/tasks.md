# Tasks

## 1. Focus

- [x] 1.1 `GuideRow`: when the focused cell's id is no longer drawn, focus the cell covering now (in the window) or the window's start (design 1, 2).
- [x] 1.2 `EPGStore`: `IPTV_TESTEPGDELAY=<s>` delays applying listings in debug builds (design 3); documented in DEVELOPMENT.md.

## 2. Verification

- [x] 2.1 UI test, demo server with `IPTV_TESTEPGDELAY=15`: in the guide, Down twelve times quickly from the first row; after the programmes arrive the focused cell is in the row reached (its channel id from the identifier), never in a row above; screenshot.
- [x] 2.2 `GuideUITests`, `GuideEmptyChannelsUITests`, `ArchiveUITests` and the full Apple TV UI suite green.
- [ ] 2.3 Real Apple TV, Release build: the user scrolls fast through the guide of their provider.
