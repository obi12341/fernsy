# Design

## Context

Today Fernsy uses the system accent (blue by default) and system colours, and each view
styles logos and posters on its own:

- **Channel logos:** `ChannelRow` shows them 48×30 without a background. `GuideView` has
  its own logo cell.
- **Posters:** `PosterCard` (MovieViews.swift) already has overlays for favourite,
  watched, unwatched count, progress and resume. Its placeholder is a film symbol. The
  rating sits below the title.
- **Sidebar:** `LibraryView` uses a native `List` in a `NavigationSplitView`, with sections
  IPTV and Jellyfin and a small footer showing "Gültig bis" and "Stand".
- **Images:** `ImagePipeline` downsamples and caches images in an `NSCache`.

The design source is the Claude Design project "Fernsy Redesign", section "Gestaltung" and
`Sidebar.dc.html`.

## Goals / Non-Goals

**Goals:**
- Shared tokens and components that later screen changes use without restyling.
- A visible improvement right away where the components replace old code: logos, poster
  placeholder and sidebar.

**Non-Goals:**
- Rebuilding screens (Live TV rows, guide, player, details); each has its own change.
- A custom sidebar instead of the native one.

## Decisions

### 1. Accent colour through the asset catalog

`AccentColor` is added to `Assets.xcassets`: #6C65F0 for any appearance and #958FFF for
dark. `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor` is set in both build
configurations, so `Color.accentColor`, tint, selection and buttons follow without code
changes. On macOS the user's own accent colour (System Settings) still takes precedence over
the app's, which is the platform's rule and is kept.

The colour tokens that are not system colours are named constants in
`Fernsy/Views/Design/Theme.swift`, each resolving per appearance:
- `Theme.record`: red, for recording and live
- `Theme.warning`: amber
- `Theme.logoTile`: graphite #2C2B33
- `Theme.logoTileLight`
- `Theme.tagBorder`

Rejected: replacing all system colours with a custom palette. System backgrounds, text and
separator colours already adapt to both appearances and to accessibility settings
(increase contrast).

### 2. Logo tile with a measured tone

`LogoTile(url:name:width:)` is a 13:8 rounded rectangle (radius scaled with the width) with
the logo fitted inside a 12 % inset. When there is no logo, or it does not load, the tile
shows the channel's initials:
- the first letters of up to three words
- for a one-word name, its first two letters

`ImagePipeline` measures the tone once per decoded logo. It takes a 16×16 RGBA thumbnail,
the share of transparent pixels, and the mean luminance of the opaque ones. A logo with more
than 20 % transparency and a mean luminance below 0.35 is "dark on transparent" and gets
the light tile. The tone is cached next to the image under the same key.

Rejected: always a light tile in the light appearance. Most IPTV logos are made for dark TV
screens (white text), so they would disappear on light. The design keeps graphite in both
appearances for that reason.

### 3. Poster placeholder and rating on the poster

`PosterCard`'s placeholder becomes a neutral surface (`.quaternary`) with the title set in
semibold, centred, up to 4 lines. The same placeholder is used when the image fails to load.
`RemoteImage` reports failure by staying on the placeholder, which needs no change.

The rating moves onto the poster as "★ 7,3" (top left, small dark capsule) when there is no
unwatched count. The favourite stays top right. The line below the title then only shows
the subtitle (year).

### 4. Status badge component

`StatusBadge(kind:)` has the kinds `playing`, `recording`, `scheduled`, `favorite`,
`offline`, `hidden`, `live` and `behind(String)`. Each renders symbol plus text in the
token colours, so later changes only place it. In this change it is only built and used in
the sidebar; Live TV rows and the player adopt it in their own changes.

### 5. Sidebar status

These stay native: the `List` sidebar, plus the following additions.
- **Recordings badge:** "Aufnahmen" gets `.badge(Text("\(n) läuft"))` in `Theme.record`
  while recordings run. It disappears when none does.
- **Jellyfin header:** `Section` gets a custom header: "Jellyfin", then a dot and text, a
  green dot with the server name, or an amber dot with "Offline" (`JellyfinStore.isOffline`).
- **Footer:** the existing footer gets the account's host as its first line, then "Gültig
  bis …" and "Stand HH:MM".

Rejected: the design's floating sidebar panel as a custom view. The macOS 27 sidebar is
already an inset, rounded surface, and a custom one would lose native selection, keyboard
navigation and accessibility.

### 6. Adoption in this change

- `ChannelRow` (Live TV list, search, favourites) and the guide's channel column use
  `LogoTile`.
- `PosterCard` uses the new placeholder and the rating capsule.

Everything else waits for the screen changes.

## Risks / Trade-offs

- **The accent changes everywhere at once.** That includes places the redesign has not
  touched yet. This is intended, because it is the brand colour, but the screenshots for the
  App Store will need an update with the redesign.
- **Brightness measurement costs a little CPU per logo.** It runs on the image task's
  detached thread, together with downsampling, on a 16×16 thumbnail.
- **Initials for exotic names.** Names starting with digits or symbols fall back to the
  first two visible characters.
