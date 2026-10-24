# Proposal

## Why

The redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f) rests on shared building blocks that every screen uses: one palette
for dark and light, the violet accent from the app icon, a logo tile, poster cards, status
markers and a floating sidebar. Today each view styles these on its own. Without a common
foundation, the screen changes that follow would drift apart, and the light appearance would
need to be fixed screen by screen. This change comes first; all other redesign changes build
on it.

## What Changes

- **Design tokens**:
  - colours for dark and light: window, raised surfaces, separators, text levels
  - the accent: #958FFF / #6C65F0 in dark, #5B53E0 in light for contrast
  - red, used only for recording and live
  - amber, for warnings and offline
  - Dark stays the primary appearance; light follows the system.
- **Type and spacing**: a typography scale (SF Pro, Dynamic Type, tabular figures for times),
  a 4-pt spacing grid and radii as the source defines them in "Gestaltung".
- **Logo tile**: every channel logo sits on a 13:8 graphite tile with fixed padding, in
  both appearances. Dark logos on a transparent background get a light tile; Fernsy measures
  the logo's brightness once and caches the result.
- **Poster card**: 2:3 with radius 8. Rating, favourite, resume progress and watched or
  unwatched badges are overlays. A missing poster shows the title on a neutral surface.
- **Status markers**: always symbol plus text, never colour alone: In Player, REC,
  Scheduled, Favourite, Offline, Hidden, LIVE, −12:34.
- **Sidebar**:
  - floats as a rounded panel, with IPTV and Jellyfin groups
  - a recording badge ("1 läuft") on Aufnahmen
  - a Jellyfin status dot with text (Heimserver / Offline)
  - a footer with the IPTV account name, valid-until date and catalog timestamp
- **Search**: the search field stays at the right of the toolbar on every screen.

Out of scope:
- Rebuilding individual screens; each has its own change.
- The app icon and the website.
- iPad and Apple TV, which the design only outlines as an outlook.

## Capabilities

### New Capabilities

- `appearance`: the shared visual rules that are user-visible behaviour: dark and light,
  logo tiles with brightness detection, poster placeholders, markers that never rely on
  colour alone, and the sidebar with account and server status.

### Modified Capabilities

- `catalog`: the sidebar shows the account status footer and the recording badge.
- `jellyfin-library`: the Jellyfin group in the sidebar shows the server status.

## Impact

- New `Fernsy/Views/Design/` with tokens, `LogoTile`, `PosterCard`, `StatusBadge` and the
  sidebar.
- `Fernsy/Support/ImagePipeline.swift`: logo brightness measurement, cached with the image.
- `LibraryView.swift`: the sidebar.
- `Assets.xcassets`: named colours for both appearances.
- Later redesign changes depend on this one.
