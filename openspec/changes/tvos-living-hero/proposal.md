# Proposal

## Why

The large entry at the top of Start (and the suggestion on Jellyfin's Übersicht) shows a still
backdrop. Streaming apps make that spot feel alive when it has focus. Fernsy should too, but
without video: a preview stream would take one of the provider's connections (single-stream
accounts) and YouTube trailers cannot play on tvOS (user decision 2026-10-28: "nur lebendiges
Bild").

## What Changes

- While the large entry has focus, its backdrop moves slowly (Ken Burns: a gentle zoom and pan
  over ~20 s, back and forth) and, when the title has more than one backdrop, cross-fades to the
  next one every ~8 s.
- Moving focus away lets the picture settle on its current image; no motion while the rows below
  have focus.
- Title, facts and buttons fade and rise in when the entry changes (another suggestion, a new
  item to continue).
- With "Reduce Motion" on, the picture stays still and only cross-fades.
- Several backdrops per title: Jellyfin's backdrop list, and the provider's `backdrop_path` list
  (the app keeps only the first today).

Out of scope: video previews and trailers (user decision); the Mac app; poster cards.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: new requirement for the living backdrop of the large entry.

## Impact

- FernsyTV: a shared `LivingBackdrop` view used by Start's backdrop (`StartBackdrop`) and, once
  `tvos-jellyfin-overview` is merged, its spotlight; focus of the large entry passed to it.
- FernsyCore: `MovieDetails` and `SeriesInfo` keep all backdrops; `JellyfinStore.backdropURLs`.
- UI test with screenshots at two moments; Start's scroll measurement must stay under its limit.
