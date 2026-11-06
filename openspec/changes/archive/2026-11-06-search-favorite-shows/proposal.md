# Proposal

## Why

The Mac's toolbar search finds channels, films, series, Jellyfin titles and recordings, but not
what runs on TV. Searching "Tatort" finds no episode that airs tonight on a favourite channel,
although the guide knows it. Apple TV and iPhone/iPad already list live TV shows in their search.

## What Changes

- The toolbar search on the Mac also searches the guide of the favourite channels (at most 50)
  and shows a new group "Shows" with the shows that run now or later and whose title matches:
  channel, day and time, and whether the show runs now.
- The guides of the favourite channels are loaded when a search starts, if they are not loaded
  yet; the group fills in as they arrive, without blocking typing.
- Selecting a show that runs now plays its channel; a later show offers to record it (or shows
  that it is planned). A context menu offers play, record and opening the channel's guide.
- Same exclusions as today: hidden channels and categories, adult categories while they are off.

Out of scope:
- Channels that are not favourites (recently watched, all channels): the guide is loaded per
  channel, so searching every channel would mean hundreds of requests per search.
- Past shows, also on catch-up channels.
- Matching show descriptions; only titles count, as on Apple TV and iPhone/iPad.
- Apple TV, iPhone/iPad, the MCP tool `search_program` and the assistant: unchanged.

## Capabilities

### New Capabilities

### Modified Capabilities
- `search`: the search across all sources gains live TV shows of the favourite channels, with
  their own group, order, actions and loading behaviour.

## Impact

- `Fernsy/Views/SearchResultsView.swift`: `SearchResults`/`SearchModel` get the show hits, the
  view a "Shows" group with show rows.
- `Fernsy/App/FernsyActions.swift` / `AppModel`: favourite channels for the search, guide
  loading (`loadGuides`) and `EPGStore.search` reused; recording through `Recorder.schedule`.
- Localizable strings (German), unit tests for matching, order
  and limits (the Mac app has no UI test target; checks run in Fernsy Dev on the demo server).
- No new network requests beyond the guide requests the favourites' guide view already makes.
