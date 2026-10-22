# Tasks

## 1. Index and query

- [x] 1.1 `SearchIndex`: flat entries for channels, films, series, recordings, Jellyfin films and series with folded keys; visibility and adult rules applied; rebuilt in the background on source or setting changes
- [x] 1.2 Query path: 150 ms debounce, cancellable background search, ranking (prefix, word start, anywhere; then name), grouped result with totals and capped hits; measure with the real-size catalog benchmark (≥ 48,000 entries) that a query takes well under 50 ms off the main thread, and record the numbers in design.md

## 2. Results view

- [x] 2.1 `SearchResultsView` with groups (channels with `ChannelRow`, posters for films/series of both accounts, recordings), "show all (n)" per group, "no results" state; `LibraryView` shows it while the query is not empty (not in Live TV Edit mode), prompt "Fernsy durchsuchen"
- [x] 2.2 Acting on hits: channel and recording play, films and series open their detail in the navigation stack; remove the per-section `query` filters (keep the Edit-mode channel filter)
- [x] 2.3 Verify on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo) with a debug switch `IPTV_TESTSEARCH=<query>` that types the query after the catalog is loaded: grouped hits from Live TV, films and series (window screenshot via `screencapture -l`), selecting a channel plays it, clearing restores the section; hidden channel and adult category not found (`IPTV_TESTHIDE`); Edit mode still filters – done with `IPTV_TESTSEARCH="light|fog|xyz|"`: grouped hits (channels, films, series), ranking (word start before inside a word), "no results", clearing restores the section; `IPTV_TESTHIDE=channel:101` drops "Northern Light 1 HD" from the results and showing it again brings it back; Edit mode filters the list with the hidden channel dimmed. Not run: selecting a hit by click (no mouse input on the user's screen; same `app.play`/`NavigationLink` as Favorites), Jellyfin and recordings groups (no Jellyfin account or recordings in the test runs), adult categories (the demo has none; same rule as the sections)

## 3. Finish

- [x] 3.1 Translations (xcstringstool sync, no untranslated keys), README note (global search, `IPTV_TESTSEARCH`); `openspec validate --all --strict`

## Workflow follow-up

- Archive after the user's review, then merge `change/add-global-search` into `main` with the user's OK.
