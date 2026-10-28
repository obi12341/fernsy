# Design

## Context

- `GuideRow` (FernsyTV/Screens/GuideScreen.swift) draws a channel's shows in the visible
  3-hour window as `Button`s placed by `offset` on a time axis. With no shows in the window it
  draws a plain `Text` ("Loading program …" / "No program information"), which the focus engine
  cannot reach; gaps between shows draw nothing.
- Each show cell pages the window with Left/Right at its edges (`page(_:show:windowEnd:)`).
- `ChannelGuide.entries` is nil while loading and empty when the provider has no listings.
- The Mac shows a hatched bar for rows without data ("No program data" with the hint "The channel
  plays anyway · double-click to watch") and has `IPTV_TESTNOEPG=<channel id>` to produce such a row.

## Goals / Non-Goals

**Goals:**
- Every row of the guide can take focus and play its channel.
- Focus moving down the guide lands on a nearby cell, as between rows with shows.

**Non-Goals:**
- Inventing listings or filling gaps with "unknown show" entries elsewhere (channel list, Start).

## Decisions

1. **Gap cells from the window's shows.** `GuideGaps.free` (FernsyCore, unit-tested) computes the
   free stretches of the window:
   before the first show, between shows, after the last, or the whole window when there is
   none. Stretches of 15 minutes or more become `GuideGapCell` buttons with the same height,
   offset logic and `GuideCellStyle` as shows, a hatched fill like the Mac's, and only the text "No
   program data": the Mac's hint line is left out (user decision 2026-10-28; on the remote the
   focused bar shows by itself that it can be clicked). Shorter gaps stay empty: a sliver cell would be hard to see
   and to hit. Rejected: making the channel column (logo and name) focusable instead (it would
   add a focus stop to every row, also those with shows, and Left from a show would no longer
   reach the rail).

2. **While loading.** With `entries == nil` the whole window is one gap cell reading "Loading
   program …"; it plays the channel like the others, so focus does not wait for the network.

3. **Click plays the channel** (`model.zapSource = model.liveSource; model.play(channel)`), the
   same path as a running show. Nothing is offered for recording: without a show there is no
   time span to schedule.

4. **Paging.** Gap cells take the show cells' `onMoveCommand` with their own start and end, so
   Right at a gap reaching the window's end moves the window by an hour, and Left at its start
   moves back, as from shows.

5. **`IPTV_TESTNOEPG=<channel id>` on Apple TV** (debug builds): the row treats that channel's
   listings as empty, as the Mac's guide does.

6. **Identifiers.** `guide.<channel id>.gap.<start epoch>` for gap cells, and the value
   `loading` or `empty`, so tests address them like show cells.

## Risks / Trade-offs

- [More focus stops in rows with sparse listings] → gaps under 15 minutes are left out.
- [Hatched cells look like content] → muted colours and the explicit text, as on the Mac.
