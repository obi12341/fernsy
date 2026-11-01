## Context

Episode codes are built by hand in eleven places: `"S\(s) F\(n)"` in FernsyCore's `StartBuilder`
(Continue Watching, Jellyfin episode lines), `TVModel+Library`, `TVModel+Details` (episode rows,
Jellyfin rows) and the Apple TV `StartScreen`; `"S\(s) E\(n)"` in the Mac's `StartView`,
`SeriesViews` and `AppModel` (player subtitle); `"S1E2"` without a space in `NextEpisodeOverlay`
and `AppModel` (Jellyfin next-episode text). None of them is localized.

The next episode for IPTV series is chosen twice: the Mac's `SeriesViews.nextEpisode` (resume
position, else first unwatched, else first; episodes sorted by number) and `TVModel.nextEpisode`
(resume position, else after the last watched, else first; episodes in the provider's order
within a season), used by Apple TV and iOS. Jellyfin series use the server's Next Up on all apps.

## Goals / Non-Goals

**Goals:**
- One localized code and one rule, each in FernsyCore, used by all three apps.

**Non-Goals:**
- Changing what counts as watched (last 90 s) or how resume positions are stored.
- Jellyfin's next episode and the MCP tools' fields.

## Decisions

### 1. `ItemText.episodeCode(season:episode:)` with a string catalog entry
English source `"S%lld E%lld"` in FernsyCore's catalog, German `"S%lld F%lld"`; the unit test
reads the German form from the package's `de.lproj`, as `LocalizationTests` do (a `locale:`
argument only changes number formatting, not the language). Callers append " · title"
themselves, as today.
Rejected: keep "S1 F2" in all languages (English users read "F" as nothing); spelled out
"Staffel 1, Folge 2" (too long for cards and rows).

### 2. The Apple TV rule, in `SeriesInfo.nextEpisode(position:watched:)`
Decided with the user (2026-11-01): resume position first, else the episode after the last
watched one, the first when none is watched, the last when all are. The function takes closures
for position and watched state, so the Mac (`AppModel`) and `TVModel` pass their own stores. It
sorts by season, then episode number, as the Mac did; the Apple TV took the provider's order,
which is the same for well-formed catalogs.
Rejected: the Mac's "first unwatched" rule (sends a viewer who skipped an episode or watched a
season out of order back to the gap, unlike Weiterschauen and Jellyfin's Next Up).

## Risks / Trade-offs

- [Mac users see a different "next episode" than before for series with gaps] → intended; noted
  in the release note.
- [Providers with episode numbers out of order] → sorting by number may change the Apple TV's
  pick for such series; the number order is what the page shows, so it is the expected one.

## Migration Plan

Code only; no stored data changes. Rollback: revert the commit.

## As built

- `JFItem.episodeCode` / `episodeLine` and `Episode.code` wrap `ItemText.episodeCode`; a Jellyfin
  episode without season or number shows its name alone instead of "S0 F0".
- `IPTV_TESTWATCHED` moved into `DebugEnv.watchedKeys`, so the Apple TV and iOS apps read it too
  (the new UI test `LibraryUITests.testDemoSeriesSkippedEpisode` needs it). `launchDemo` takes
  launch arguments for the language.
- Verified in the test VM (Library, Start, iOS suites) except playback tests, which cannot pass
  there (no hardware video decoding in the VM, DEVELOPMENT.md › Test VM); the Mac on the host.
