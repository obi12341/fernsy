# Design

## Context

- The Apple TV player is a `fullScreenCover` over the tab view (`RootScreen`); closing it shows
  whatever the tab under it shows. Start has a `NavigationStack(path:)` of `DetailTarget`s;
  Jellyfin's Übersicht (`JellyfinScreen`) has a `NavigationStack` without a path and two
  destination types (`DetailTarget`, `JellyfinOverview.Tile.Kind`).
- Start's "Weiterschauen" cards already have `.contextMenu { Details }`, shown only when
  `DetailTarget.of(entry.open)` is not nil. `DetailTarget.of` returns nil for a Jellyfin episode,
  so those cards get no menu. Start's `info(_:)` already maps a Jellyfin episode to its series
  (`jellyfin.series` by `seriesId`), but falls back to the episode itself when the series is not
  in the list.
- "Nächste Folge" on Start (`wideRow`) and both rows on Übersicht have no menu.
- `TVModel.play(_:fromStart:)` plays from the start on request. The series page
  (`DetailScreen`) already offers the episode to continue with (Jellyfin's Next Up or the IPTV
  rule) and selects its season.

## Goals / Non-Goals

**Goals:**
- From any card in these rows the series is one long press away, for IPTV and Jellyfin alike.
- After an episode from these rows, Back lands on its series page.

**Non-Goals:**
- Mac and iPhone/iPad (see proposal).
- The Top Shelf, search and the assistant: they start playback outside these rows.

## Decisions

### 1. The series page goes beneath the player when the episode starts

When an episode starts from "Weiterschauen", "Nächste Folge" or Start's large entry, the row's
screen pushes the series page onto its navigation path and then starts playback. The player
covers it; when the player closes for any reason (Back, end, failure), the series page is what
shows, and Back from it pops to Start or Übersicht.

Rejected: pushing the series page when the player closes (a close hook in `RootScreen` with a
request the tab consumes). It needs a new model property, a request per tab and care with the
cover's dismiss animation, for the same result. Rejected: a different Back behaviour inside
the player (closing the player into a page from there): the player does not know the tabs.

Not pushed when the series page is already the top of the path (the episode was started from
it; scenario "Series page unchanged").

### 2. The series of an episode: one lookup for menu and Back

A `DetailTarget.series(for:)` (in `TVModel+Search.swift`) returns the page for an entry's
series: `.series(series)` for an IPTV episode, `.jellyfin(seriesItem)` for a Jellyfin episode,
where the series item is `jellyfin.series` by `seriesId`, else a lookup through
`jellyfin.loadDetail(seriesId)`. If none is found (offline, unknown series), there is no "Zur
Serie" item and nothing is pushed: playback works as today. This replaces the fallback in
`info(_:)` that opened the episode itself as a page.

### 3. One menu view for both screens

A `ContinueCardMenu(entry:...)` (Start's `LibraryEntry`; Übersicht's `JFItem` mapped to a
`LibraryEntry` target) with: "Fortsetzen" (progress) or "Abspielen", "Von Anfang an" (progress),
"Zur Serie" or "Details", in that order, each with a symbol so the UI tests find the cells
(`play.fill`, `backward.end.fill`, `rectangle.stack`, `info.circle`). "Zur Serie" opens the page
without playing; it is the same push as decision 1.

### 4. Übersicht gets a navigation path

`JellyfinScreen` gets `@State path = NavigationPath()` bound to its `NavigationStack`, so it can
push the series page itself; the genre and decade tiles keep their `NavigationLink(value:)`.

## Risks / Trade-offs

- [The series page appears beneath while the player loads] → it is covered by the player; its
  loading (episodes, details) happens while playback starts. Measured in the UI test that the
  player still starts within its usual time.
- [Someone who wants the next card in "Weiterschauen" needs one more Back] → accepted (user's
  choice); the series page offers the next episode, which is what most people want after one.
- [A Jellyfin series not loaded yet] → decision 2 loads it; until then the menu has no "Zur Serie".
