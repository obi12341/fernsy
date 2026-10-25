# Design

## Context

`NowNextLine` (`ChannelListView.swift:234`) and `ChannelDetailPane.body`
(`ChannelDetailPane.swift:29`) compute `let now = Date()` while drawing. Both observe only
the channel's `ChannelGuide`, which changes when the programme loads. When time passes and
nothing else changes, they are not redrawn. The progress bar, the current show and the next
show all stay as they were.

`GuideView` already solves the same problem with `TimelineView(.periodic(from:by: 30))`, and
`RecordingsView` does it every 5 s.

`ChannelRow` loads the programme in `.task(id: channel.id)`, so only when the row appears.
`EPGStore.isFresh` treats a programme as fresh when either:
- it reaches more than 20 h ahead, or
- it is younger than 1 h,

and in both cases it is under 12 h old. A row that stays visible for hours never asks
again.

## Goals / Non-Goals

**Goals:**
- Rows and pane are at most a minute behind the clock.
- A visible row keeps its programme fresh.

**Non-Goals:**
- Second-accurate progress.
- Changes to the guide grid, the player or the freshness rule.

## Decisions

### 1. `TimelineView(.everyMinute)` around the time-dependent parts

`NowNextLine` and the pane's content are drawn inside `TimelineView(.everyMinute)` and use
`context.date` instead of `Date()`. `.everyMinute` fires at each full minute. Shows start on
full minutes, so the change appears right away instead of up to 30 s late.

Only the time-dependent part is wrapped:
- in the row, the second line; the name, logo and marks are not redrawn;
- in the pane, the whole body, because current show, list of following shows and buttons all
  depend on "now".

Rejected:
- **One shared `@Published` minute clock in `AppModel`:** every observer of `AppModel`
  would redraw every minute. That is the whole library, not just the visible rows.
- **`.periodic(by: 30)` as in the guide:** it is up to 30 s late at a show change. That is
  no cheaper per row, and it does not land on the minute.

### 2. A visible row checks freshness every five minutes

`ChannelRow`'s task becomes a loop:
1. load the programme;
2. wait five minutes (`Task.sleep`, which is cancelled when the row disappears);
3. when `EPGStore.needsRefresh(channelId)`, which is `!isFresh`, load again; repeat.

The existing download limits stay: two full tables at a time, newest request first, and
cancellation when no view waits any more. Many visible rows can therefore not start a flood
of downloads.

Rejected: a timer in `EPGStore` that reloads every known channel. That would also download
channels nobody is looking at.

### 3. Verification without waiting for a real show change

A debug switch `IPTV_CLOCKOFFSET=<s>` shifts the time used for "now" in rows and pane (and
only there). For example, a list opened at 22:28 with an offset of 120 s behaves as if it
were 22:30.

Rejected: a switch that fakes the clock everywhere. The player, the recordings and the demo
server would then disagree with each other.

Instead, the test opens the list on the demo server just before a show change of the demo
EPG and takes screenshots before and after it. If the demo's shows are too long for that,
`IPTV_CLOCKOFFSET` places the list two minutes before a change.

The reload in decision 2 is checked separately. `IPTV_CLOCKOFFSET` does not reach
`EPGStore`'s freshness rule, which keeps using the real clock. Two switches cover it instead:
- `IPTV_EPGRECHECK=<s>` shortens the five minutes;
- `IPTV_EPGSTALE=1` makes `needsRefresh` true.

The log then has to show a fetch for each visible row, and none for rows that have
disappeared.

## Risks / Trade-offs

- **[Redrawing every minute costs CPU]** → only visible rows exist in the `List`. Each one
  redraws one line once a minute; the cost is negligible.
- **[A loop per visible row]** → it sleeps 5 minutes between checks and only downloads when
  the programme is stale. Scrolling cancels it.
