# Tasks

## 1. Client and session

- [x] 1.1 Get Jellyfin credentials from the user (scratchpad only, mode 600) and verify `/System/Info/Public` answers
- [x] 1.2 `JellyfinClient` with auth header, sign-in, user views, items paging, seasons/episodes, resume/next-up/latest, played/favorite writes, logout; verify each endpoint against the user's server with a small debug run or test harness and note the route forms used
- [x] 1.3 `JellyfinStore` session handling: keychain item "jellyfin" (no password), device id, restore on launch, 401 → expired; verify relaunch restores the session and a revoked token shows the expired notice

## 2. Accounts in the app

- [x] 2.1 `FernsyApp`/`AppModel`: library shown with any account; IPTV and Jellyfin independent; verify signing out of one keeps the other (debug run with demo IPTV + Jellyfin)
- [x] 2.2 `LoginView` IPTV/Jellyfin picker and Jellyfin form with error messages (no server / wrong password); `SettingsView` Jellyfin section with Add/Sign Out; verify each message and the sheet by screenshot
- [x] 2.3 `NSLocalNetworkUsageDescription` (de/en); verify the Release build reaches a LAN server in the sandbox

## 3. Library

- [x] 3.1 Load libraries, films and series with paging and cache; verify item counts match the server and a relaunch shows the cache before the refresh
- [x] 3.2 Sidebar groups and category column (All, Favorites, libraries, genres, counts); verify by screenshot
- [x] 3.3 Poster grids with year/rating, sorting (added, name, release date, rating), search, watched marks/progress/unwatched counts; verify against the web client for a few items
- [x] 3.4 Film detail and series detail (seasons, episodes, thumbnails, streams summary, disabled Play); verify by screenshots of one film and one series
- [x] 3.5 Home rows (Continue Watching, Next Up, Recently Added); verify they match the web client's home
- [x] 3.6 Mark watched/unwatched (item, season, series) and favorites with optimistic update and error revert; verify on one test item each and restore its state
- [x] 3.7 Offline: cached library with a notice when the server is unreachable; verify by pointing the session at an unreachable port in a debug run

## 4. Finish

- [x] 4.1 Translate new strings (xcstringstool sync, no untranslated keys) and document the Jellyfin account and minimum server version in README
- [x] 4.2 Remove test credentials from the scratchpad and verify no host, user or token is in the repository or logs

## Workflow follow-up

- Archive after the user's review, merge `change/add-jellyfin-library-browser` into `main`.
- Next change: Jellyfin playback (direct play, track selection, progress reporting).
