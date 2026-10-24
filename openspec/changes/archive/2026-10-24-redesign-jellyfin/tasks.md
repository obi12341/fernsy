# Tasks

## 1. Views

- [x] 1.1 `JellyfinStatusBanner` in the IPTV notice style (offline, expired, error). Verify: debug run with `JF_SERVER=http://127.0.0.1:9` (unreachable, no real server touched) shows the offline banner (screenshot).
- [x] 1.2 Home header with server name and status, wide cards with `ProgressBar`, and "Als Nächstes". Verify: same run (Home shows the header with "Offline").
- [x] 1.3 Grid sort segment, and detail pages with `DetailBackdrop`, the meta line and the season segment. Verify: build. The data-dependent screens are checked by the user with their own server.

## 2. Localization and verification

- [x] 2.1 Strings (de + en), with no stale keys. Verify: build.
- [x] 2.2 Debug/Release builds. `openspec validate redesign-jellyfin --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- The user checks Home, grid and details with their Jellyfin server in the next DMG.
- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
