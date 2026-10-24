# Proposal

## Why

The poster grids and detail pages show little at a glance: the rating, favourite and resume
state are hidden, a missing poster leaves a hole, and runtimes are shown as "02:04:00". The
redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f), `Filme.dc.html`, `FilmDetail.dc.html` and `SerieDetail.dc.html`, puts
this information on the poster and gives the detail pages a calmer hierarchy.

## What Changes

- **Movie grid**: posters with rating (★ 7.3), favourite and resume progress as overlays. A
  visible sort segment replaces the menu, and a missing poster shows the title.
- **Film detail**:
  - the backdrop runs under the toolbar and fades into the window background
  - no category column on detail pages
  - poster, title, year, runtime as "2 Std. 4 Min.", genre and rating
  - "Fortsetzen" with position and remaining time, or "Abspielen", plus a favourite button
  - plot, then director, cast and file information as a quiet list
- **Series detail**:
  - "Nächste Episode" as the main action, naming season, episode and title
  - seasons as a native segment
  - episodes with image, progress in the image, duration, "Gesehen" (check plus text), and
    "Als Nächstes" on the next one
- **Light appearance**: film detail in light, with the backdrop fading to white.

Out of scope:
- Jellyfin screens (see `redesign-jellyfin`), which reuse these components.
- Catalog loading and caching.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `catalog`: poster overlays, the sort segment, the poster placeholder, and the detail page
  layout (backdrop, runtime format, resume information, crew list).

## Impact

- `MovieViews.swift`, `SeriesViews.swift`, `LibraryView.swift` (hide the category column
  on detail pages).
- Depends on `redesign-foundation`.
