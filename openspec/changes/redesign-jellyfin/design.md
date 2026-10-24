# Design

## Context

`JellyfinViews.swift` already uses the foundation's `PosterCard`, so watched checks,
unwatched counts, favourites and the rating capsule are in place. The views are:

- **Grid:** `JellyfinGridView`, with a sort menu in the toolbar.
- **Home:** `JellyfinHomeView`, with paged carousels: Weiterschauen and Nächste Folge as
  wide cards with a system `ProgressView`, Neue Filme and Neue Serien as posters.
- **Details:** `JellyfinDetailHeader`, with a 320 pt backdrop below the toolbar, and the
  film and series detail views.
- **Status:** `JellyfinStatusBanner`, a yellow strip for offline, expired session and
  errors.

The sidebar shows the server state since `redesign-foundation`. Detail pages collapse the
category column since `redesign-movies-and-series` (same `NavigationStack`).

The design source is Claude Design "Fernsy Redesign", `JellyfinStart.dc.html` and the
"Jellyfin offline" state.

## Goals / Non-Goals

**Goals:**
- Jellyfin looks like the IPTV screens: the same cards, bars, banners and detail layout.
- The server state is visible in several places.

**Non-Goals:**
- Merging sources.
- Playback, sign-in.
- A timestamp of the cached library. The store keeps none, so the notice says "gespeicherte
  Bibliothek" without a time.

## Decisions

1. **Status banner.** The banner gets the IPTV notice's shape: rounded, `Theme.warning` at
   13 %, symbol, title plus line, and the action button on the right.
   - **Offline:** "Jellyfin nicht erreichbar" with "Du siehst die gespeicherte Bibliothek."
     and Erneut versuchen.
   - **Expired session:** Neu anmelden.
   - **Errors:** OK.
2. **Home header.** A first line shows the server name (title2, bold) and a status dot with
   text: "Verbunden" in green, or "Offline" in amber.
3. **Cards.** Wide cards use `ProgressBar` (4 pt, accent) inside the image, as in IPTV
   episode rows. "Nächste Folge" is renamed "Als Nächstes" to match the series detail.
4. **Grid sort.** A segmented picker: Hinzugefügt, Name, Erscheinung, Bewertung.
5. **Detail pages.**
   - **Backdrop:** they use `DetailBackdrop` (380 pt) with `.ignoresSafeArea(edges: .top)`
     and a hidden toolbar background, like IPTV.
   - **Meta line:** "2024 · 2 Std. 4 Min. · FSK 12 · ★ 7,3 · Genre, Genre", using
     `runtimeText`.
   - **Season selection:** a segment when there are 2–6 seasons, a menu above that.

## Risks / Trade-offs

- **Visual verification is limited.** Fernsy must not touch the user's Jellyfin server from
  debug builds. Only states that work without a server can be checked: the offline banner
  with an unreachable debug server, and empty Home. The full Home with data is checked by
  the user.
