# Design

## Context

- **Mac** (`Fernsy/Views/StartView.swift`): `StartLiveCard` reads `Date()` in `body` but only
  redraws when its `ChannelGuide` publishes, i.e. when new guide data arrives. The live rows'
  guides are loaded once in `.task(id: channel ids)` with `epg.load`, and `rows.tonight` is
  computed once there. Leaving Start and coming back recreates the view, which is why
  "hin und her" fixes it.
- **Channel list** (Mac): `NowNextLine` sits in `TimelineView(LiveClock.everyMinute)` and rows
  call `epg.keepFresh`, which reloads a guide every 5 min when it is no longer fresh.
  `LiveClock` (in `ChannelListView.swift`) counts minutes in seconds (calendar `.everyMinute`
  stalls in the repeated DST hour) and has `IPTV_CLOCKOFFSET` in debug builds.
- **Apple TV / iOS** (`FernsyTV/Screens/StartScreen.swift`, `FernsyiOS/StartView.swift`): the
  same shape – `StartLiveCard` / `LiveCard` use `model.currentShow(on:)` with `Date()`,
  guides through `model.loadGuide(for:)` (`EPGStore.load`) once, `rows.tonight` once. No
  minute clock exists in the tvOS/iOS targets; `EPGStore.keepFresh` is not used there.

## Goals / Non-Goals

**Goals:**
- Jetzt live and Heute Abend stay current on all three platforms while Start is shown.
- One clock rule per platform family, testable with a clock offset.

**Non-Goals:**
- Other screens, catalog rows (see proposal).

## Decisions

### 1. Minute timeline around the live cards
Each live card's content is drawn in `TimelineView(<minute schedule>)` and reads "now" from the
context date (plus the debug offset), like `NowNextLine`. The progress bar moves with it.

Rejected:
- **A timer in the view model that republishes the rows:** redraws the whole Start (backdrop,
  posters) every minute; the timeline redraws only the cards.

### 2. A shared minute clock for Apple TV and iOS
`LiveClock` moves to a file shared by the tvOS and iOS targets (`FernsyTV/Support/LiveClock.swift`,
the synced FernsyTV folder compiles it into the iOS app too; only the listed screens are excluded), with the same seconds-based
schedule and `IPTV_CLOCKOFFSET`. The Mac keeps its own copy in `ChannelListView.swift`.

Rejected:
- **FernsyCore:** it does not import SwiftUI, and `PeriodicTimelineSchedule` is SwiftUI.
- **Calendar `.everyMinute`:** stalls in the hour that repeats when daylight saving time ends.

### 3. `keepFresh` instead of `load` for Start's channels
Start's guide task calls `EPGStore.keepFresh` per live channel in a task group, cancelled when
Start disappears or its channels change, so guides are reloaded when they run short (at most
two downloads at a time, as the store limits them).

### 4. Heute Abend recomputed per minute
`rows.tonight` is recomputed when the minute changes (a `.task` that sleeps to the next full
minute and recomputes, while Start is shown) and when a guide arrives, using the same
`StartBuilder.tonight` rules, so ended shows drop out and the title switches at 21:30.

Rejected:
- **Recomputing inside the row's `TimelineView`:** the row's item list would change during a
  focus move on Apple TV; a state change between minutes is calmer.

## Risks / Trade-offs

- **Focus on Apple TV:** if the focused card in Heute Abend drops out, focus moves to a
  neighbour. Accepted; it is a show that ended.
- **More guide reloads:** only for Start's at most 12 channels and only when stale, the same
  rule the channel lists use.
- **Mac schedule ticks on the real minute:** the Mac's `LiveClock.everyMinute` starts at the
  real minute, the tvOS/iOS one at the shifted minute. With `IPTV_CLOCKOFFSET` the Mac card
  therefore changes up to a minute after the show does; without an offset both are the same.
- **Tests (found while writing them):** a SwiftUI button joins its label's texts into its
  accessibility value ("Dream Homes, Dream Homes, …"), so the UI tests check that the value
  contains the title; launching takes longer than 20 s on a busy simulator, so the clock is set
  60 s before the change.
  The tests set `IPTV_EPGSTALE=1`: a guide table cached on the simulator from an earlier day can
  differ from what the demo server sends now, and the test reads the server directly.
