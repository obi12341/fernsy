# Proposal

## Why

After `tvos-live` the Apple TV app watches and records live TV. The design
(`AppleTV.dc.html`, Claude Design project "Fernsy Redesign") also has the library half: a
Start screen, the provider's films and series, Jellyfin and a search across everything. On the
Mac these are half of what Fernsy does; on Apple TV, the screen in the living room, films and
series matter at least as much.

## What Changes

- New tabs Start (first tab, the app opens on it), Filme, Serien, Jellyfin and search (icon),
  in the design's order: Start, Live TV, Programm, Filme, Serien, Jellyfin, Aufnahmen, search,
  gear.
- Start (screen `home`): a large "Weiterschauen" item with backdrop, facts and "Fortsetzen ·
  noch …", the "Weiterschauen" row across IPTV films and episodes, Jellyfin and recordings with
  their source, and "Zuletzt hinzugefügt" from IPTV and Jellyfin.
- Filme and Serien (screen `filme`): the IPTV account's films or series as a poster grid with
  rating and "Neu", a category picker and the sorting Zuletzt hinzugefügt, A–Z, Bewertung,
  Erscheinungsjahr.
- Film page (screen `film`): backdrop, title, facts (year, genre, runtime, rating, quality,
  age rating), description, "Fortsetzen · <position>" or "Abspielen", "Von vorn", favourite,
  resume progress, and director, cast, audio and subtitle languages.
- Series page (screen `serie`): source, seasons, "Nächste Episode · S2 F4", favourite, a
  season picker and the episodes with watched marks, "Als Nächstes" and progress.
- Jellyfin (screen `jellyfin`): the server's state, the views Übersicht, Filme, Serien and
  Bibliotheken, "Weiterschauen" and "Zuletzt hinzugefügt" with unwatched counts. Signing in
  to Jellyfin from the welcome screen and from Settings › Konto hinzufügen.
- Search (screen `suche`): the query with an on-screen letter row (with ä, ö, ü, space and
  delete), dictation and typing on the iPhone, results while typing: live TV (running now or
  coming up) and films and series from IPTV and Jellyfin with their source.
- Playing films, episodes and Jellyfin items in the Apple TV player with resume, audio and
  subtitle tracks, the next episode countdown and Jellyfin progress reporting, as on the Mac.

## Capabilities

### New Capabilities

None. The Apple TV behavior stays in `apple-tv`.

### Modified Capabilities

- `apple-tv`: the tab bar gets Start, Filme, Serien, Jellyfin and search; new requirements for
  Start, films and series, their pages, Jellyfin, search and on-demand playback; the welcome
  screen offers Jellyfin.

## Out of Scope

- Changes to the Mac app's behavior; code only moves into the packages.
- Syncing watched state or favourites of IPTV films between Mac and Apple TV (Jellyfin keeps
  them on its server anyway).
- Music, live TV and other Jellyfin library types (as on the Mac).
- Top Shelf, the final app icon, a real-device test and TestFlight.

## Impact

- `FernsyTV/Screens/`: Start, grids, detail pages, Jellyfin, search.
- Jellyfin client, store and playback (`Fernsy/Jellyfin/`), the search index and the IPTV
  watched/resume state move into `FernsyCore` and `FernsyPlayer` so both apps use them; the Mac
  app's behavior stays the same.
- Jellyfin on Apple TV identifies itself as its own device; debug builds keep their own device
  id (lesson from `dev-build-isolation`).
- Debug MCP and UI tests grow; the local Docker Jellyfin test server is used for checks.
