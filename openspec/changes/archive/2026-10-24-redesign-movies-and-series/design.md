# Design

## Context

**Grids:** `MovieViews.swift` holds the movie grid, `SortMenu` (a toolbar menu),
`PosterCard` and `MovieDetailView`. `PosterCard` already has the foundation's title
placeholder and rating capsule, and overlays for favourite, watched, unwatched count,
`fraction` progress and a "Fortsetzen" badge.

**Details:** `SeriesViews.swift` holds the series grid, `SeriesDetailView` (backdrop,
poster, meta, season segment, `EpisodeRow` list) and `FavoritesView`.

**Resume:** `AppModel.saveResume` stores only the position (`resume.<key>` in
`UserDefaults`, removed under 30 s or within the last 90 s). There is no duration and no
watched state for IPTV media.

**Layout:** the detail pages are pushed on the detail column's `NavigationStack`, with the
category column still visible.

**Design source:** Claude Design "Fernsy Redesign", `Filme.dc.html`, `FilmDetail.dc.html`
and `SerieDetail.dc.html`, dark and light.

## Goals / Non-Goals

**Goals:**
- Grids and details as in the source.
- Progress and "watched" visible without opening an item.

**Non-Goals:**
- Jellyfin screens (`redesign-jellyfin`).
- Syncing watched state anywhere. It stays local, like resume positions.

## Decisions

### 1. Resume duration and watched flags

`saveResume` also stores the duration (`resume.<key>.duration`) when known. A position in
the last 90 s marks the item watched (`watched.<key>` = true) before the resume position is
removed; playing it again from the start leaves the flag. `AppModel.resumeFraction(key)`
and `isWatched(key)` read them.

Test runs without the keychain share the installed app's defaults. They therefore keep
watched flags in memory, as they do for recent channels.

Rejected: deriving "watched" from a missing resume position. A position is also missing for
never-started items.

### 2. Grid

`SortMenu` becomes a segmented `Picker` in the toolbar (Neueste, Name, Bewertung). Movie
posters get `fraction` from the stored duration, so the progress bar appears together with
the existing "Fortsetzen" badge. Series posters show no progress.

### 3. Detail pages

**Layout:**
- While the detail stack is not empty, `LibraryView` collapses the category column, as it
  does in guide mode.
- The backdrop (height 360) ignores the top safe area, so it runs under the transparent
  toolbar, and fades into the window background.

**Film detail:**
- **Meta line:** year · runtime as "2 Std. 4 Min." (parsed from the provider's "HH:MM:SS"
  or "N min") · genre · "★ 7,3".
- **Main action:** "Fortsetzen" with "1:12:40 · noch 51 Min." when a position exists,
  otherwise "Abspielen". Next to it "Von vorne" (only when resuming) and the favourite
  toggle.
- **Below:** the plot, then a two-column "Details" grid with Regie, Besetzung, Genre and
  Format.

**Series detail:**
- **Main action:** "Nächste Episode · S1 E3 · Title". It is the episode with a resume
  position, otherwise the first one that is not watched; when everything is watched, it is
  the first episode.
- **Season segment:** shown as today.
- **Episode rows:** image with a progress bar from the resume fraction, title, duration,
  "Gesehen" (✓ + text) or "Als Nächstes" (accent label), and the plot.

## Risks / Trade-offs

- **Watched flags only exist from now on.** Episodes watched before this change appear
  unwatched until they are played again.
