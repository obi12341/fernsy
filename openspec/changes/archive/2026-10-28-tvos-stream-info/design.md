# Design

## Context

Both apps play through `PlayerEngine` in `FernsyPlayer`, which publishes `stats` once per
second and a `BufferHistory`. The Mac's `StatsOverlay` (`Fernsy/Views/PlayerScreen.swift`)
builds its rows inline from those and draws the chart with Swift Charts; the I key toggles it
(`IPTV_SHOWINFO` at launch). The Apple TV players (`PlayerScreen`, `VODPlayerScreen`, the
recording player in `RecordingsScreen`) show nothing of it.

## Goals / Non-Goals

**Goals:**
- The same rows on both platforms from one definition.
- A TV-sized panel that never takes focus.

**Non-Goals:**
- A shared SwiftUI view for both platforms (sizes and materials differ too much).

## Decisions

### A. A setting, not a remote gesture

"Technische Infos" is a switch under Settings › Wiedergabe (`@AppStorage`), and while it is on
every player shows the panel. Someone looking into a problem keeps it on for a while; a
setting survives switching channels and players.

Rejected:
- **A remote button**: the Siri Remote has no free button (click, Menu, Play/Pause and the
  touch surface are all taken by the player).
- **An entry in the live overlay's Info tab**: would not reach the VOD and recording players,
  which have no tabs, and would close with the overlay.
- **Debug builds only**: the point is to look into problems on a real Apple TV with the
  Release build, like the Mac's I key that every user has.

### B. Rows in `FernsyCore`

A `StreamInfo` type in `FernsyCore` (changed while building: the plan said `FernsyPlayer`, but
`PlaybackStats` lives in FernsyCore and only FernsyCore has a test target) turns `PlayerStats` (and the status) into an ordered
list of label/value pairs, with labels and formats localized in the package's string catalog.
The Mac's `StatsOverlay` and the TV panel both render that list; each platform keeps its own
view, sizes and chart styling. The chart's data comes from the engine's `BufferHistory`, which
both already have.

Rejected: copying the rows into the TV app (two lists drift apart, as the Mac's list grew over
several changes); moving the Mac's whole view into the package (Mac sizes and material do not
fit 10-foot viewing).

### C. Placement on TV

Top-right, inside the safe area, under the player overlay in z-order, `allowsHitTesting(false)`
and not focusable, so focus and the remote behave as without it. It sits 120 pt from the top,
below the live player's recording badge, and is sized (17 pt monospaced, chart 100 pt high) so
it ends above the film player's progress bar. The chart is the Mac's `BufferChart` at TV size
(`TVBufferChart`); tvOS ignores a font set on the whole chart, so the axis labels carry it.

## Risks / Trade-offs

- [Moving the Mac's rows changes Mac code] → The Mac overlay must show the same rows and
  values as before; checked with `IPTV_SHOWINFO=1` against the demo server before and after.
- [German labels exist in the Mac catalog today] → Move them with the same translations into
  the package catalog; the Mac catalog entries go away once unused.
