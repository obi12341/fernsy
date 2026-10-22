# Design

## Context

- `LibraryView` has one `.searchable` toolbar field (`query`) and hands it to the open section:
  `ChannelListView`/`GuideView` (`filteredChannels`), `MovieGridView` (`filteredMovies`),
  `SeriesGridView`, `FavoritesView`, `RecordingsView`, `JellyfinGridView` (`jellyfin.filtered`).
  The Jellyfin home switches to the films grid while a query is typed.
- All data is local and in memory: `AppModel.channels/movies/series` (Xtream, cached on disk,
  each with a precomputed `searchKey` = `makeSearchKey(name)`, case- and diacritic-folded),
  `Recorder.recordings`, `JellyfinStore.films/series` (cached library, no precomputed key).
- Visibility rules already exist: `isHidden(channel)`, `hiddenCategoryIDs`, `showAdult`.
- Navigation: the detail stack already has destinations for `Movie`, `Series` and `JFItem`
  (`LibraryView.swift`), so results can push the same detail views.
- Measured on a real provider catalog (48,735 channels, films and series): `contains` over the
  folded keys takes 12–23 ms per query on the main thread (scratchpad benchmark).

## Goals / Non-Goals

**Goals:** one toolbar search over all local sources with grouped, ranked, capped results that
stays fluid on catalogs of ~50,000 entries.

**Non-Goals:** episodes, guide programmes, server-side search, history (see proposal).

## Decisions

### Search index, built off the main thread
`SearchIndex` holds one flat array of entries `(source, id, name, key)` for all sources; it is
rebuilt in a background task when a source changes (catalog refresh, recordings, Jellyfin
library, visibility or adult setting) – the keys of Xtream items are reused, Jellyfin and
recording keys are folded once there. Visibility and adult rules are applied when building, so
the query path only matches strings.
- Rejected: filtering the live arrays on each keystroke on the main thread – 20+ ms per key
  plus SwiftUI diffing of up to 35,000 hits ("a") makes typing stutter.
- Rejected: SQLite FTS or a prefix tree – substring matching ("tort" finds "Tatort") is the
  existing behaviour and is fast enough without a new dependency.

### Query path
Typing updates `query` immediately; the search runs 150 ms after the last keystroke in a
detached task over the index snapshot (cancelled by the next keystroke) and publishes the
grouped result on the main actor. Ranking: 0 = name starts with the query, 1 = a word starts
with it (after a space or punctuation), 2 = elsewhere; then `localizedStandardCompare`. Each
group keeps its total and its first 12 hits (posters) or 20 rows (channels, recordings);
"show all (n)" expands that group in place (lazy grid/list).

### Results view replaces the section while a query is typed
`LibraryView.detail` shows `SearchResultsView` whenever `query` is not empty – except in Live
TV's Edit mode, where `ChannelListView` keeps filtering (hidden channels included) as today.
The section's own `query` filters are removed; the category and sorting choices stay.
Clearing the field shows the section as it was (its category and scroll position are untouched
because the section view was only replaced, not reset). The prompt becomes "Fernsy durchsuchen".
- Rejected (by the user): a separate "Search" section, or section filter plus "search
  everywhere" below it.

### Acting on hits
Channels play via `app.play(channel)`, recordings via `app.play(recording)`; films and series
of both accounts are appended to the detail navigation path (existing destinations). Channel
rows reuse `ChannelRow` (logo, now/next), posters reuse the existing poster views.

## Measurements

`SearchIndex.search` compiled on its own with a benchmark over the real provider catalog
(48,735 entries, scratchpad): 20–21 ms per query, 36 ms for "a" (35,290 hits, sorting
included); building the entries from the cached JSON took 215 ms including folding (in the
app the Xtream keys already exist). Both run off the main thread.

## Risks / Trade-offs

- [Memory: a second array of ~50,000 small entries] → a few MB; keys are shared strings.
- [Index staleness right after a catalog refresh] → rebuilt on every source change; the old
  snapshot stays usable meanwhile.
- [Losing the per-section filter (user decision)] → category browsing and sorting stay; the
  Edit-mode filter stays for hiding channels.
