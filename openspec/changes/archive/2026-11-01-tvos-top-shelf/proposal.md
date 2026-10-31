# Proposal

## Why

When Fernsy's icon has focus in the top row of the Apple TV Home Screen, tvOS shows the app's
Top Shelf above it. Today that is a stand-in image: the Mac icon and the word "Fernsy" on
purple, rendered by `scripts/make-tv-icons.swift`, which calls itself a stand-in "until the
designed Apple TV icon exists". It looks unfinished, and it wastes the most visible place an
Apple TV app gets. Media apps (TV, Infuse, Plex) put the user's own content there, so a click
continues watching without opening the app first.

## What Changes

- A Top Shelf extension shows the user's content as rows of tiles. All of them come from what
  Start already shows, so hidden channels and adult content stay out, as on Start:
  - **Continue Watching:** IPTV films and episodes and Jellyfin items in progress, with
    backdrop, title and progress.
  - **Favorite channels:** with logo and the show on now (or, without favorites, the recently
    watched channels as on Start).
  - **Recordings:** finished recordings, newest first.
- Selecting a tile plays it (film or episode from its position, channel, recording). Clicking
  opens Fernsy on the item's page where there is one.
- Without an account or content, and before Fernsy ran once, tvOS shows a newly designed static
  Top Shelf image instead of the stand-in: the sunset landscape of the icon across the full
  width, with the TV and the name kept small. The dev build keeps its orange "DEV" band.
- The app keeps the Top Shelf current: it writes what to show (and the images) to a shared
  container when Start's rows change, and tells tvOS to reload.
- Signing out of an account removes its items from the Top Shelf.
- The app icon's layers: the TV alone in front of the indigo background, instead of the Mac
  icon's whole rounded square (which showed as a square inside the tvOS icon).

Out of scope:
- A carousel-style Top Shelf (one large backdrop with summary at a time). The rows show more,
  and the carousel suits a single catalog; it can follow later.
- Live previews (video) in the Top Shelf.
- Mac, iPad and iPhone: Top Shelf exists only on tvOS.
- Redesigning the app icon's motif.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: new requirements for the Top Shelf content, its actions, and the static image.

## Impact

- **New target:** a tvOS TV Top Shelf extension (`FernsyTopShelf`, bundle id
  `de.mobilistics.fernsy.topshelf`, dev `de.mobilistics.fernsy.dev.topshelf`) in
  `Fernsy.xcodeproj`, embedded in the Apple TV app.
- **App Group:** `group.de.mobilistics.fernsy` (dev: `group.de.mobilistics.fernsy.dev`) in the
  app's and the extension's entitlements. Registered through automatic signing; no App Review
  note expected.
- **URL scheme:** `fernsy://` in the Apple TV app's Info.plist for the tile actions. This needs
  an edit of `Config/Info-TV.plist`, which holds the user's own uncommitted change; that task
  waits for the user's go-ahead (tasks.md).
- **FernsyTV:** a snapshot writer next to the Start rows, URL handling that opens or plays an
  item (sharing the parsing with the debug MCP tool `play_item`), and strings in English and
  German.
- **`scripts/make-tv-icons.swift`:** the new static Top Shelf images (normal and wide, @1x and
  @2x, normal and dev).
- **Release:** the App Store build embeds the extension; CI builds it with the app.
