# Tasks

## 1. Settings and catalog

- [x] 1.1 Add `showsIPTVMovies` / `showsIPTVSeries` to `AppModel` (UserDefaults `library.iptvMovies` / `library.iptvSeries`, default on) with `IPTV_SHOWMOVIES=0|1` / `IPTV_SHOWSERIES=0|1` in memory only; document both in `DEVELOPMENT.md`; verify a debug run with the demo server and `IPTV_SHOWMOVIES=0` leaves `defaults read de.mobilistics.fernsy library.iptvMovies` unchanged
- [x] 1.2 Make `refresh` download only enabled sections and `loadFromCache` decode only enabled ones; check `isEmpty(section)` and the empty-library checks; verify in the event log of a demo run with `IPTV_SHOWMOVIES=0 IPTV_SHOWSERIES=0` that the refresh's changed actions contain no `get_vod_*`/`get_series*`
- [x] 1.3 Switching off clears the section and deletes its cache files; switching on downloads that section at once (also while a refresh runs); verify with a demo run toggling through a debug hook or Settings, watching `ls` of the account cache directory and the log

## 2. Library and search

- [x] 2.1 Sidebar lists Movies/Series only while on; the selected hidden section falls back to Live TV; verify with `IPTV_SHOWSERIES=0` (window screenshot of the sidebar) and by switching off while Series is open
- [x] 2.2 Favorites column leaves out "Filme"/"Serien" while off, favorites keys stay; verify with `IPTV_SHOWMOVIES=0` and a film favorite set beforehand in a demo run (the "Filme" row is gone, it returns with `IPTV_SHOWMOVIES=1`)
- [x] 2.3 Search finds no IPTV films/series while off; verify with `IPTV_SHOWMOVIES=0 IPTV_TESTSEARCH=<demo film title>` (no "Filme" group; channels still found)

## 3. Settings UI

- [x] 3.1 Add the toggles "Filme" and "Serien" with the footnote to the IPTV section of `AccountsSettings`; sync `Localizable.xcstrings` with English ("Movies", "Series", note); verify with `IPTV_TESTSETTINGS=accounts` (window screenshot) in light and dark (`IPTV_APPEARANCE`)

## 4. Integration

- [x] 4.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; run `openspec validate --all --strict`
- [x] 4.2 Check the toggles end to end (switch off, search, switch on) in a debug run against the demo server with `IPTV_SHOWMOVIES`, `IPTV_SHOWSERIES`, `IPTV_TESTSWITCHMEDIA` and `IPTV_TESTSEARCH`: sidebar, cache files, log and search results as specified
