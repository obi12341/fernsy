# Proposal

## Why

`tvos-foundation` gave the Apple TV app a model, playback and plain placeholder screens. The
Apple TV screens are now designed in Claude Design (project "Fernsy Redesign", file
`AppleTV.dc.html`, 15 screens). This change builds the live TV half of that design, so the app
is usable for its main job, watching live TV with the Siri Remote. The library half (Start,
films, series, Jellyfin, search) follows in `tvos-library`.

## What Changes

- A top tab bar as in the design, with the tabs this change brings: Live TV, Programm,
  Aufnahmen and Settings (gear). Start, Filme, Serien, Jellyfin and search are added by
  `tvos-library`. The app opens on Live TV.
- First launch and sign-in: a welcome screen to choose the kind of account, and the IPTV form
  (server, username, password; typing from the iPhone works), "Anmelden" and "Demo-Zugang
  testen" (signs in to the public demo server). The Jellyfin card appears with
  `tvos-library`.
- Live TV: a category column (Favoriten, Zuletzt gesehen, Alle Sender, pinned categories,
  "Alle Kategorien"), the channel rows (number, logo, name with tags, favourite star, REC mark,
  current show with progress and time left), and a pane with a live preview of the focused
  channel, now and next. Click tunes in, Play/Pause switches the preview's sound on, a long
  press offers Aufnehmen, Favorit and Ausblenden.
- "Alle Kategorien": all categories as a grid with country filters, a category search, and
  pinning or hiding a category by long press.
- Programm: the guide grid for the chosen category with a now line, played or recorded from
  the grid.
- Player: an overlay with the tabs Info, Untertitel, Ton and Sender, a timeline over the
  timeshift buffer (buffer start, position, live point, a running recording), the time behind
  live, and a channel strip that slides up with Down to zap with now and next.
- Recordings on Apple TV, which `tvos-foundation` ruled out: record now or schedule from the
  guide, with padding, stored where tvOS may delete them, and only while Fernsy is open. The
  Aufnahmen tab shows running, scheduled, finished and failed recordings and plays them.
- Settings: accounts, add account, Wiedergabe, Aufnahmen (padding), Protokoll and the version.
- Favourites, hidden and pinned categories and channels, and recently watched channels work
  on Apple TV as on the Mac and are kept per account on the Apple TV.

## Capabilities

### New Capabilities

None. The Apple TV behavior stays in `apple-tv`.

### Modified Capabilities

- `apple-tv`: the designed navigation, sign-in, Live TV, all categories, guide, player and
  settings; recordings on Apple TV replace "SHALL NOT record".

## Out of Scope

- Start, Filme, Serien, the film and series pages, Jellyfin and search (`tvos-library`).
- "Mit Mac abgleichen" (iCloud) and "Jugendschutz" from the design's settings screen: both
  are dropped (user decision 2026-10-26), not deferred.
- Syncing favourites, hidden items or recordings between Mac and Apple TV; playing the Mac's
  recordings on Apple TV.
- Top Shelf, the final Apple TV app icon, a real Apple TV device test and TestFlight.
- Changes to the Mac app's behavior. Code moves into the packages only.

## Impact

- `FernsyTV/Screens/` replaced by the designed screens; `FernsyTV/Model/` grows (favourites,
  visibility, pins, history, recordings, settings).
- Shared logic moves from the Mac app into the packages so both apps use it: favourites,
  visibility, pins and channel history into `FernsyCore`; the recorder into `FernsyPlayer`
  (without AppKit). The Mac app's behavior stays the same.
- The Apple TV debug MCP gets tools for recordings; the UI tests grow.
- `FernsyTV/Localizable.xcstrings` (English source, German translation).
