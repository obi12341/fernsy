# Proposal

## Why

The user also runs a Jellyfin server with their films and series. The playback analysis
(`openspec/changes/archive/2026-10-20-analyze-jellyfin-playback`) showed that Fernsy's
player can play almost the whole library directly. Before wiring up playback, Fernsy needs
a Jellyfin account and a browser for films and series that sits next to the IPTV library.

## What Changes

- Sign in to a Jellyfin server (server URL, username, password) in addition to the IPTV
  account; both can be signed in at the same time. Only the access token is stored (keychain).
- The sidebar gets a "Jellyfin" group with Home (Continue Watching, Next Up), Films and
  Series; the category column lists the server's libraries and genres plus "Favorites".
- Poster grids, film detail and series detail (seasons, episodes) with Jellyfin metadata
  and artwork, sorting and search.
- Watched status (check mark, progress bar) and Jellyfin favorites, shown and changeable;
  changes are written to the server.
- The library cache works offline-first like the IPTV catalog.

Out of scope (separate changes): playback of Jellyfin items (second run; Play is shown but
not functional yet), music, live TV/DVR from Jellyfin, several Jellyfin servers or users
at once, Quick Connect, editing metadata, App Review demo content for Jellyfin.

## Capabilities

### New Capabilities
- `jellyfin-account`: signing in to a Jellyfin server, keeping and removing the session.
- `jellyfin-library`: browsing Jellyfin films and series, home rows, watched status and favorites.

### Modified Capabilities
- `catalog`: "Library sections and categories" – the sidebar lists the IPTV sections only
  with an IPTV account and gains the Jellyfin group with a Jellyfin account.

## Impact

- New `Fernsy/Jellyfin/` (client, models, store), new views for the Jellyfin group,
  `LoginView`/`SettingsView` (account choice and Jellyfin section), `LibraryView` (sidebar
  groups), `FernsyApp` (library shown when any account exists), `Keychain.swift` (second
  keychain entry), `Localizable.xcstrings`.
- Tests need the user's Jellyfin server again (credentials at implementation time, kept in
  the scratchpad only).
