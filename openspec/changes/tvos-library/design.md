# Design

## Context

- Builds on `tvos-live` (tab bar, sign-in, player overlay, recordings, shared live state in
  `FernsyCore`). Screens from `AppleTV.dc.html`: `home`, `filme`, `film`, `jellyfin`, `serie`,
  `suche`, and the Jellyfin card of `login`.
- On the Mac, the Jellyfin client, store and playback are in `Fernsy/Jellyfin/`
  (`JellyfinPlayback` imports `CFFShim`, `FernsyPlayer`, VideoToolbox), the search index in
  `Fernsy/App/SearchIndex.swift`, IPTV film and series lists, favourites and watched state in
  `AppModel`. `ContentHistory` (resume positions) is already in `FernsyCore`.
- The Mac's Jellyfin requests identify the device; `dev-build-isolation` gave debug builds a
  device id of their own after debug sign-ins signed the user's app out.

## Goals / Non-Goals

Goals: the designed library screens from shared code, so films, series, Jellyfin and search
behave as on the Mac.

Non-goals: new library features beyond the design; Mac behavior changes.

## Decisions

### A. Jellyfin and search move into the packages

`JellyfinClient` and `JellyfinStore` move into `FernsyCore`, `JellyfinPlayback` into
`FernsyPlayer`; the search index and the IPTV film/series state (lists, favourites, watched,
"Neu") move into `FernsyCore`. Platform parts stay in each app: the device name (Mac name vs.
Apple TV name), image loading and the windows. Rejected: tvOS copies (the play-method and
progress-reporting rules of `jellyfin-playback` are subtle and tested on the Mac).

### B. Device identity on Apple TV

The Apple TV app sends its own stable device id (stored in its keychain) and the Apple TV's
name, so the server lists it next to the Mac. Debug builds use a separate id, as on the Mac.
Rejected: sharing the Mac's device id (universal purchase shares the bundle id, not the
keychain item on another device, and a shared id signs devices out, see `dev-build-isolation`).

### C. Start merges sources by recency

"Weiterschauen" merges IPTV resume entries (`ContentHistory`), Jellyfin's resume list and
partly watched recordings, sorted by last played. The large entry is the newest of them.
"Zuletzt hinzugefügt" interleaves the newest IPTV films/series and Jellyfin items by added
date. Rejected: one row per source (the design shows one row with source badges).

### D. Search with its own letter row

The design shows the query and an inline letter row instead of tvOS' full-screen keyboard, so
search uses a custom focusable letter row writing into the query, plus `.searchable`'s
dictation and iPhone input through a hidden system text field. Results come from the shared
index (task A) with the Mac's matching and order; live TV results come from `EPGStore` for
favourites and recently watched channels, as the Mac's `search_program` does. Rejected:
`.searchable` alone (its tvOS keyboard covers the results the design shows next to it).

### E. Posters and backdrops

Images load through a small image pipeline in the Apple TV app (memory and Caches), sized to
the tile. Rejected: `AsyncImage` (no disk cache; grids of hundreds of posters reload on every
scroll).

### F. Verification

Checks use the demo server (films, series, posters) and the throwaway Docker Jellyfin
`fernsy-jf-fixtures` on 127.0.0.1:8097 (removed after each use), never the user's Jellyfin.
Screens are compared with the rendered design screens; the debug MCP gets `play_item` for
films, episodes and Jellyfin ids.

## Risks / Trade-offs

- [Large catalogs make grids and search slow on Apple TV] → lazy grids, the shared index built
  off the main thread; check with the demo server and a synthetic 50,000-entry catalog as on
  the Mac.
- [Jellyfin transcoding rules depend on decoders the Apple TV has] → the play-method decision
  asks the platform which codecs it decodes; checked with the fixture clips.
- [Moving Jellyfin code could change the Mac] → Mac regression on the Docker Jellyfin (play,
  resume, progress, next episode) before archiving.

## Migration Plan

None: stored Mac data keeps its keys; the Apple TV app's library data is new.
