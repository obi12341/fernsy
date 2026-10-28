# Proposal

## Why

The Apple TV app got a Start page across IPTV and Jellyfin (tvos-start-rows, tvos-living-hero)
and a Jellyfin Übersicht that helps discover the library (tvos-jellyfin-overview). The Mac app
has neither: it opens on Live TV, and its Jellyfin "Home" shows four plain rows. Both apps
should offer the same way into the library (user request 2026-10-28).

## What Changes

- A new sidebar entry "Start" above the IPTV and Jellyfin groups; the app opens on it.
- Start on the Mac shows what Start shows on Apple TV: the large entry (newest item to continue,
  else the newest film) over its backdrop with "Fortsetzen"/"Abspielen" and "Details", then
  Jetzt live, Weiterschauen, Nächste Folge (Jellyfin), Heute Abend, Zuletzt hinzugefügt, the
  largest film and series categories and Jellyfin genres, Deine Aufnahmen and Bestbewertet, each
  only with entries. Clicks behave as elsewhere on the Mac (channels play in the player window,
  films and series open their pages, a later show offers to record it).
- The large entry's backdrop moves (slow zoom and pan, cross-fade between the title's backdrops)
  while the mouse is over the entry, and rests otherwise; Reduce Motion keeps only the
  cross-fade (user decision 2026-10-28).
- Jellyfin's "Home" becomes "Übersicht" with the Apple TV's content: the suggestion with
  "Anderer Vorschlag", Weiterschauen, Zuletzt hinzugefügt, Deine Favoriten, Ungesehen & top
  bewertet, Kurz & gut, Serien fast durch, Wieder entdecken, genre and decade tiles opening a
  sortable grid, and the library in numbers. Its German name changes from "Start" (which now
  belongs to the new page) to "Übersicht".
- Rows page with previous/next buttons as the Jellyfin rows do today, so a mouse without a
  horizontal wheel reaches every card.
- The rules that pick Start's rows move from the Apple TV app into FernsyCore, so both apps
  build the same rows from the same data.

Out of scope: the Apple TV pages themselves (unchanged in behavior); video previews in the large
entry (rejected for Apple TV, same reasons); a customizable Start (choosing or ordering rows).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `catalog`: the sidebar gains "Start" at the top, opened at launch; a new requirement for the
  Mac's Start page.
- `jellyfin-library`: the group's first entry becomes "Übersicht"; "Home rows" is replaced by
  the overview's content.

## Impact

- Fernsy (Mac): `LibrarySection` gains `start`, `jellyfinHome` shows the overview;
  `LibraryView` sidebar and launch selection; new views for Start, the large entry, the
  overview, the browse grid; a Mac `LivingBackdrop` driven by hover.
- FernsyCore: Start's row rules (today `TVModel.startRows`, `continueWatching`, `recentlyAdded`,
  `tonight`) as a pure builder with unit tests; `LibraryEntry` moves there. `JellyfinOverview`
  is already in FernsyCore.
- FernsyTV: uses the moved builder (no visible change); its Start and overview UI tests guard it.
- Strings: new Mac texts with German translations; "Home" renamed.
- Tests: FernsyCore unit tests for the builder; Mac UI checks with the demo server and the local
  Jellyfin test server.
