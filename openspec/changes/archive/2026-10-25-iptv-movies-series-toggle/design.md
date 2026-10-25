# Design

## Context

The IPTV catalog is three independent sections in `AppModel` (`CatalogSection.live/movies/series`,
each with two `CatalogAction`s). A refresh downloads all six actions in parallel, writes each to
`<account cache>/<action>.json` and decodes only the sections whose bytes changed (or that are
still empty). The sidebar lists `LibrarySection.iptv` (a static array). Search builds its
index from `app.movies`/`app.series` (`SearchResultsView` snapshot), `FavoritesView` filters
`app.movies`/`app.series` by favorite keys, while the Favorites category column counts favorite
keys (`movie:`/`series:` prefixes) without looking at the catalog.

Settings that change what the library shows (`showAdult`, `showAdultInRecent`) are `@Published`
properties on `AppModel`, stored in `UserDefaults` under `library.*`, with `IPTV_*` overrides
that keep them in memory (`debugSettingsInMemory`).

## Goals / Non-Goals

**Goals:**
- One place decides whether films/series are on; everything downstream follows from the
  catalog arrays being empty plus the sidebar list.
- Switching off saves the download and memory, not only the UI.

**Non-Goals:**
- Touching stored favorites, watched marks, resume positions or series track memory.

## Decisions

- **Two settings on `AppModel`: `showsIPTVMovies`, `showsIPTVSeries`** (`UserDefaults`
  `library.iptvMovies` / `library.iptvSeries`, default true via `object(forKey:) == nil`).
  Same pattern as `showAdult`, so the debug overrides work the same way.
  Rejected: `@AppStorage` in the views (the catalog refresh in `AppModel` needs the value too)
  and per-account storage in the account's cache directory (only one IPTV account exists; the
  preference is about the user, who has Jellyfin, not about the provider).
- **Switched off = not in the catalog.** `refresh` downloads only the actions of enabled
  sections; `loadFromCache` decodes only enabled sections; switching off clears the section's
  arrays and categories and deletes its two cache files. Search, `FavoritesView`, deep links
  and `IPTV_AUTOPLAY` lookups then find nothing without their own checks.
  Rejected: keep downloading and filter in every view (search, favorites, grids each need the
  check; the large VOD downloads continue for nothing).
- **Switching on downloads that section at once**, through a section-scoped refresh that is
  not blocked by the general `refreshInFlight` guard; if a full refresh is running, the toggle
  waits for it and then fetches the section, so a switch never gets lost.
- **Sidebar list is computed:** `LibrarySection.iptv` becomes a function of the two settings
  (or the view filters it). If the selected section becomes hidden, `LibraryView` sets
  `section = .live` and clears the navigation path.
- **Favorites column:** the "Filme"/"Serien" rows are left out while switched off (they count
  favorite keys, which are kept). The "Alle" favorites view shows only channels then.
- **Place in Settings:** the IPTV section of Settings › Accounts, as two toggles under the
  account details ("Filme", "Serien") with a footnote "Ausgeschaltete Bereiche werden nicht
  geladen und nicht durchsucht." Shown only while signed in to IPTV.

## Risks / Trade-offs

- [The user switches films off and on often] → each switch-on downloads the VOD list again; it
  is the same request as a normal refresh, accepted.
- [Empty-catalog checks treat "films off" as "not loaded yet"] → `isEmpty(section)` and the
  "library is empty" checks (`channels.isEmpty && movies.isEmpty`) are reviewed so a disabled
  section never triggers a decode or a waiting loop.
- [A film is playing when films are switched off] → playback continues; only the library
  changes. The player does not need the catalog entry.
