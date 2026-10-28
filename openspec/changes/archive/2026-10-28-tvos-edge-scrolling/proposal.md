# Proposal

## Why

On the Apple TV's Jellyfin tab, scrolling looks broken: posters slide over the view switcher
(Übersicht · Filme · Serien · Bibliotheken) and vanish abruptly at the edge of the page instead of
leaving the screen. Both come from scroll views that draw outside their bounds
(`.scrollClipDisabled()`, needed so focused posters can grow) while their bounds end at the
header or at the 90-point page margin: what scrolls past those lines is still drawn over the
header, and the lazy grids and rows remove posters right there, in plain view. The horizontal
card rows (`CardRow`, used on Jellyfin's Overview, on Start and on detail pages) pop away at the
left margin the same way.

## What Changes

- Jellyfin tab: the header (title, server state, view switcher) scrolls with the content, as on
  the IPTV Films and Series tabs, so content never slides over it.
- Scroll views reach the screen edges; the page margin becomes a content margin inside them, so
  posters enter and leave at the screen edge and are only removed off-screen.
- `CardRow` does the same horizontally, which fixes the rows on Jellyfin's Overview, Start and
  detail pages at once.

No change to what is shown. Out of scope: Recordings, All Categories and the player's channel
strip (they use the same pattern; checked separately if they show the effect).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: new requirement on how content scrolls (never over headers, leaving at the screen edge).

## Impact

- `FernsyTV/Screens/JellyfinSearchScreens.swift` (JellyfinScreen layout),
  `FernsyTV/Screens/LibraryComponents.swift` (CardRow), callers that pad around CardRow
  (StartScreen, DetailScreens, JellyfinScreen overview).
- UI tests for the Jellyfin tab and screenshots of the edges before and after.
