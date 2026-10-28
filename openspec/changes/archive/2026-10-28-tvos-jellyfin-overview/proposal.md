# Proposal

## Why

The Apple TV's Jellyfin tab opens on Übersicht, which shows only "Weiterschauen" and "Zuletzt
hinzugefügt", and Start already shows both (with Next Up and two genre rows). The overview adds
nothing over Start, although the app already holds the whole library with genres, ratings,
years, runtimes, watched state, favourites and unwatched episodes. Übersicht should be the place
to discover what is in one's own library.

## What Changes

Übersicht becomes a discovery page, built from the library the app already loads (no new
server requests):

- **Spotlight** at the top: an unwatched, well-rated film with its backdrop, "Abspielen",
  "Anderer Vorschlag" (draws another) and "Details".
- **Weiterschauen** and **Zuletzt hinzugefügt** stay.
- **Deine Favoriten**: films and series marked as favourite in Jellyfin.
- **Discovery rows**: "Ungesehen & top bewertet", "Kurz & gut" (unwatched films under 100
  minutes), "Serien fast durch" (started series with at most three episodes left), "Wieder
  entdecken" (well-rated titles last watched more than a year ago).
- **Stöbern**: tiles per genre (with count and artwork) and per decade (80er, 90er …) that
  open the matching titles as a grid; a line with the library in numbers ("239 Filme ·
  69 Serien · 412 Std. ungesehen").
- Rows without entries are left out.

Out of scope (user decision 2026-10-28): rows needing new server requests (similar titles,
collections, upcoming episodes, actors); the Mac's Jellyfin home; Start.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: "Jellyfin on Apple TV" points to the new overview; new requirement for the overview's content.

## Impact

- `FernsyTV/Screens/JellyfinSearchScreens.swift` (overview, browse grid); FernsyCore
  `JellyfinOverview.swift` (rows from the library, unit-tested); `JellyfinClient.gridFields`
  only if the runtime is missing in the grid request.
- German strings; UI tests with the local test Jellyfin (`JF_TESTMANY`).
