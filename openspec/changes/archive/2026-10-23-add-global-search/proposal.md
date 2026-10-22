# Proposal

## Why

Today the toolbar search only filters the section that is open, so finding "Tatort" means
searching Live TV, then Movies, then Series, then the Jellyfin libraries one by one. One search
over everything is what the user expects. A measurement on a real provider catalog (48,735
channels, films and series) showed a plain substring match over the prepared search keys takes
12–23 ms, so a search across all sources is cheap enough to run while typing.

## What Changes

- **BREAKING (behaviour):** the toolbar search no longer filters the current section; it always
  searches everything and shows the hits grouped: channels, films, series, recordings, Jellyfin
  films, Jellyfin series (only groups of signed-in accounts and with hits).
- Hits are ranked (name starts with the query, then a word starts with it, then anywhere) and
  each group shows its first hits with "show all".
- Selecting a hit does what it does in its section: a channel or recording plays, a film or
  series (IPTV or Jellyfin) opens its detail.
- Hidden channels and adult categories stay excluded as in their sections.
- Exception: in Live TV's Edit mode the search keeps filtering the channel list (including hidden
  channels), because that is how channels are found to hide or show them.

Out of scope:
- Episodes (IPTV series load their episodes only when opened; Jellyfin episodes are not cached)
  and programme titles from the guide – possible later.
- Searching on the Jellyfin server or the provider (all data needed is already local).
- Search history or suggestions.

## Capabilities

### New Capabilities

- `search`: one toolbar search over all sources with grouped, ranked results.

### Modified Capabilities

- `catalog`: "Search per section" is removed (replaced by `search`).
- `jellyfin-library`: the poster grids no longer have their own title filter.
- `live-tv`: the list/guide switch no longer mentions search (category only); search in Edit mode.
- `channel-visibility`: hidden channels are excluded from the global search results.

## Impact

- New `Fernsy/App/SearchIndex.swift` (or similar: entries, ranking, background search),
  new `Fernsy/Views/SearchResultsView.swift`.
- `Fernsy/Views/LibraryView.swift` (routing the query to the results instead of the sections),
  `ChannelListView`, `GuideView`, `MovieViews`, `SeriesViews`, `JellyfinViews`,
  `RecordingsView` (their `query` filters go, except the Edit-mode channel filter).
- `Localizable.xcstrings` (group titles, prompt, "show all"), README.
- No new dependency, no server requests.
