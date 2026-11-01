# Tasks

Verification runs in the test VM (`scripts/vm.sh`, DEVELOPMENT.md › Test VM) against the demo
server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo, which the UI test
classes set). Watched and started episodes come from `IPTV_TESTWATCHED=episode.<id>,…` and
`IPTV_TESTRESUME=episode.<id>:<s>:<s>`.

## 1. FernsyCore

- [x] 1.1 `ItemText.episodeCode(season:episode:)` with the catalog entry `"S%lld E%lld"` → German `"S%lld F%lld"` in FernsyCore's `Localizable.xcstrings` (inserted textually)
- [x] 1.2 `SeriesInfo.nextEpisode(position:watched:)`: resume position, else after the last watched, first when none, last when all; sorted by season and episode number
- [x] 1.3 Unit tests: the code in English and German; the rule for nothing watched, a started episode, a skipped episode (1 and 3 watched → 4), all watched (→ last), across a season boundary
- [x] 1.4 `StartBuilder` uses `episodeCode` (Continue Watching, Jellyfin episode lines)

## 2. Apps

- [x] 2.1 Apple TV / iOS: `TVModel+Library` (labels and `nextEpisode`), `TVModel+Details` (episode and Jellyfin rows), `StartScreen` use the shared code and rule
- [x] 2.2 Mac: `StartView`, `SeriesViews` (code and rule via `SeriesInfo.nextEpisode`), `AppModel` (player subtitle, Jellyfin next-episode text), `NextEpisodeOverlay` use the shared code
- [x] 2.3 No hand-built `"S\(` episode code left in the app targets and FernsyCore (grep), except the MCP tools

## 3. Verify

- [x] 3.1 `scripts/vm.sh scripts/test.sh` (package tests and builds)
- [x] 3.2 `scripts/vm.sh scripts/tv-uitest.sh` with the series and Start test classes; a new or extended UI test: with `IPTV_TESTWATCHED` for episodes 1 and 3 of a demo series, the series page offers episode 4 and the code reads "S1 F4" in German / "S1 E4" in English (`-AppleLanguages`)
- [x] 3.3 `scripts/vm.sh scripts/ios-uitest.sh` (series page)
- [x] 3.4 Mac: a Fernsy Dev run with the same `IPTV_TESTWATCHED` shows "Nächste Episode · S1 F4" on the series page (screenshot) (host, English system: "Next Episode · S1 E4"; German covered by the unit test and the Apple TV test)
- [x] 3.5 `openspec validate --all --strict`

## Workflow follow-up

- Commit with release notes (users see the code in their language and a common next episode),
  archive on `change/episode-label-next-episode`, merge into `main` and push with the user's consent.
