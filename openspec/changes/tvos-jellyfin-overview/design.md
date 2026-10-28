# Design

## Context

- `JellyfinStore` holds the whole library: `films`, `series` (grid fields: genres, dates, year,
  community rating, official rating, item counts) with `userData` (played, played percentage,
  unplayed item count, favourite, last played date), plus `resume`, `nextUp`, `latestFilms`,
  `latestSeries`. Runtime (`RunTimeTicks`) is a base field Jellyfin returns with items; whether
  the grid request delivers it is checked in task 1.1.
- Übersicht today: Continue Watching (`CardRow` of `WideCard`) and Recently Added (posters).
- Start already shows Jellyfin's Next Up, Continue Watching, Recently Added and the two most
  common film genres (tvos-start-rows); the overview should not repeat those beyond the two
  rows the user wants kept.
- Start's lesson (tvos-start-scrolling): rows are built once per change of their inputs, never
  in `body`; the page is a `LazyVStack`; rows below the screen are built lazily.

## Goals / Non-Goals

**Goals:**
- A page worth opening: something new at the top, rows that answer "what could I watch?".
- No new server requests; no work per redraw.

**Non-Goals:**
- Similar titles, collections, upcoming episodes, actors (need requests; user decision).
- The Mac's Jellyfin home.

## Decisions

1. **Rows built once per library change, by a pure function in FernsyCore.**
   `JellyfinOverview.build(films:series:now:)` returns the spotlight candidates, rows, genre
   and decade tiles and numbers; it reads only `[JFItem]` and a date, so FernsyCore's unit
   tests cover the rules and the Mac could use it later. The Apple TV screen keeps the result
   in `@State` and rebuilds it in `.task(id:)` keyed on the lists' counts and a
   watched/favourite revision. Rejected: computed properties read in `body` (the stutter fixed
   on Start); building in TVModel (not unit-testable, FernsyTV has no unit test target).

2. **Rules for each row** (all from local data, each at most 20 entries, posters):
   - Spotlight: unwatched films with a backdrop and community rating ≥ 7, drawn at random
     from the top 30 by rating; "Anderer Vorschlag" draws again without repeating the last 5.
   - Deine Favoriten: `isFavorite`, films and series, newest added first.
   - Ungesehen & top bewertet: unwatched films and not-started series, rating ≥ 7.5, by rating.
   - Kurz & gut: unwatched films under 100 minutes with rating ≥ 6.5, by rating (left out if
     the runtime is missing).
   - Serien fast durch: series with some episodes watched and 1–3 left
     (`unplayedItemCount` and `recursiveItemCount`), fewest left first, badge "2 Folgen übrig".
   - Wieder entdecken: watched, rating ≥ 7, last played over a year ago, by last played.
   Thresholds are constants in one place, so they can be tuned after trying it.

3. **Stöbern opens a grid inside the tab.** Genre tiles (the genres with at least 3 titles, by
   count, with the backdrop of their best-rated title) and decade tiles (decades with at least
   3 titles) push a `JellyfinBrowse` destination: the same poster grid as Filme/Serien, filtered,
   with the sort options. Back returns to Übersicht at the same place. Rejected: switching to
   the Filme view with a filter (loses the user's place on Übersicht and mixes series out).

4. **The library in numbers** as one line under the header on Übersicht: films, series and the
   hours of unwatched films and episodes (runtime sums; series by `unplayedItemCount` ×
   their average episode runtime when known, else left out of the hours).

5. **Order on the page:** Spotlight, Weiterschauen, Zuletzt hinzugefügt, Deine Favoriten,
   Ungesehen & top bewertet, Serien fast durch, Kurz & gut, Stöbern (genres, then decades),
   Wieder entdecken. Personal rows first, discovery after, browsing near the end.

## Risks / Trade-offs

- [Small libraries leave many rows empty] → empty rows are left out; the spotlight falls back
  to any unwatched film, then disappears.
- [Ratings missing on a server] → rows that need ratings are left out; the spotlight uses any
  unwatched film with a backdrop.
- [Random spotlight changes on every visit] → it is drawn once per library load and on
  "Anderer Vorschlag", not on every appearance.
