# Proposal

## Why

Episode codes and the "next episode" differ between the apps. The Apple TV, iOS and the shared
Start rows write "S1 F2" in every language (English users see "F"), the Mac writes "S1 E2" also
in German, and the Mac's player overlay writes "S1E2" without a space. And the series page picks
a different "next episode" on the Mac (the first unwatched one) than on Apple TV and iOS (the one
after the last watched one): who skips an episode or catches up on a season lands on different
episodes per device. Both were found in `code-structure-cleanup` and left for this change.

## What Changes

- One episode code everywhere in the apps' UI: "S1 F2" in German ("Staffel", "Folge"), "S1 E2"
  in English, from one localized helper in FernsyCore. It replaces the hand-built strings on the
  Mac (Start, series page, player subtitle, next-episode overlay), Apple TV and iOS (Start,
  Continue Watching, episode rows, Jellyfin episodes) and in the shared Start builder.
- One "next episode" rule for IPTV series on all apps, the Apple TV's (decided with the user,
  2026-11-01): the episode with a resume position; otherwise the episode after the last watched
  one; with nothing watched the first; with everything watched the last. Episodes are ordered by
  season, then episode number. It moves into FernsyCore and replaces the Mac's own rule.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `catalog`: "Watched episodes and the next episode" takes the Apple TV rule; its scenario shows the
  German code.
- `apple-tv`: "Series page on Apple TV" states the rule.
- `localization`: a new requirement "Episode codes" names the code per language for all apps.

## Impact

- FernsyCore: new `ItemText.episodeCode(season:episode:)` (localized, with German string) and
  `SeriesInfo.nextEpisode(…)`; `StartBuilder` uses the code.
- Mac: `StartView`, `SeriesViews`, `NextEpisodeOverlay`, `AppModel` (player subtitle).
- Apple TV / iOS: `TVModel+Library`, `TVModel+Details`, `StartScreen`.
- No data or settings change; watched state and resume positions stay as they are.

## Out of scope

- The MCP tools' episode fields and "S1E2" codes (machine-readable, not localized).
- Jellyfin's "next episode" (the server's Next Up decides; unchanged).
- The automatic next-episode countdown after an episode ends (already plays the following one).
