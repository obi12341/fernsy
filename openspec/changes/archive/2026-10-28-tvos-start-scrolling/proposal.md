# Proposal

## Why

Scrolling down Start on Apple TV does not feel fluid. Start's `body` reads the scroll offset
(`onScrollGeometryChange` writes `@State scrolled` for the backdrop fade), so every scroll frame
rebuilds the whole screen, and the screen computes its rows inside `body`: `recentlyAdded` sorts
all films (30,000 with a large provider), `continueWatching` searches the film list for every
started film, `tonight` walks the guide of every live channel, plus Next Up and recordings.
That work runs up to 60 times a second while the user scrolls.

## What Changes

- The backdrop fade follows the scroll without rebuilding Start: the offset goes to the backdrop
  view alone.
- All rows are built once per change of what they show (catalog, resume positions, recordings,
  guide, Jellyfin), not in `body`; lookups by id instead of scans, the newest films from an
  order kept with the catalog.
- The rows below the screen are built when they come near it (lazy stack), not all at launch.
- Debug-only measuring: a large test catalog and a frame-drop counter, so the improvement is
  measured, not guessed.

No visible change to Start's content or order. Out of scope: Films/Series grids, Live TV and the
guide (own screens); the Mac app.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: new requirement that Start scrolls fluidly with a large catalog.

## Impact

- `FernsyTV/Screens/StartScreen.swift` (backdrop view, lazy stack, rows from state),
  `FernsyTV/Model/TVModel+Start.swift` and `TVModel+Library.swift` (row building, indexes).
- Debug switches `IPTV_TESTBIGCATALOG=<n>` and `IPTV_FRAMESTATS=1`; DEVELOPMENT.md.
- FernsyTVUITests: a scroll test with the large catalog that checks dropped frames.
