# Proposal

## Why

Jellyfin looks like a second app inside Fernsy. The redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f),
`JellyfinStart.dc.html` and the "Jellyfin offline" state, keeps Jellyfin as its own source
but builds it from the same cards, progress bars and badges as IPTV. The server status is
visible in several places.

## What Changes

- **Start screen**:
  - rows Weiterschauen (16:9 cards with progress), Als Nächstes and Neu hinzugefügt
  - the same card and badge components as IPTV
  - the server name and status in the header
- **Poster badges**: a "watched" check or the number of unwatched episodes, top right.
- **Offline**: when the server is unreachable, the library stays visible from the cache.
  The sidebar dot, the header and an amber notice show the status at the same time, always
  with text.
- **Film and series details**: use the layouts from `redesign-movies-and-series`.

Out of scope:
- Jellyfin playback, sign-in and the session.
- Merging IPTV and Jellyfin films into one list. The design deliberately keeps the sources
  separate.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `jellyfin-library`: home rows presentation, the poster badges, and the offline
  presentation in the sidebar, header and notice.

## Impact

- `JellyfinViews.swift`.
- Depends on `redesign-foundation` and `redesign-movies-and-series`.
