# Design

## Context

- iPhone and iPad (`FernsyiOS/GuideView.swift`): every show cell is a `Button` that calls
  `select`: a running show zaps, a past archived show plays from its start, anything else opens
  `ShowDetailSheet` (Watch Channel and `ServerRecordButton`). `ServerRecordButton` already works
  for running shows (`show.end > now`): it orders through `TVModel.orderOnServer`, which passes
  the device's streams in use and the account's limit, so the existing rule "Server order that
  would start now" refuses an order while the device holds the account's only stream.
- Apple TV (`FernsyTV/Screens/GuideScreen.swift`): `select` plays a running show, opens the
  `confirmationDialog` (Record / Don't Record, `ServerDialogButtons`) for a later one, and plays
  a past archived one from its start. The channel list already has a long-press menu
  (`.contextMenu { ChannelActions }`: Record / Stop Recording, favourite, hide), so the gesture is
  known on this platform.
- `Recorder.schedule` plans running and future shows alike (a running one starts at once, from
  the buffer when the channel plays); `recordNow` is `schedule` with the current show. Stopping a
  running recording is `recorder.stop(id)`, dropping a planned one `recorder.unschedule`.
- The Mac guide already has this menu (`Fernsy/Views/GuideView.swift`, `.contextMenu` with Play,
  `RecordButton`, `ServerRecordItem`).

## Goals / Non-Goals

**Goals:**
- A running show can be recorded from the guide on iPhone, iPad (on Fernsy Server) and Apple TV
  (on the device or the server).
- One gesture, the same on every show, without changing what a tap does.

**Non-Goals:**
- Recording on iPhone or iPad themselves.
- The Mac, Start, search, channel lists.

## Decisions

1. **Long press on every show, tap unchanged.** A tap on a running show keeps playing it (the
   most common wish in a guide); the long press opens a menu on running, later and past shows
   alike, so it means the same everywhere.
   - Rejected: a tap on a running show opening the sheet with "Watch Channel" first. It costs a
     second tap for the most common action and changes a tested, specified behaviour.
   - Rejected: the menu on running shows only. A gesture that works on some cells and does
     nothing on others reads as broken.

2. **SwiftUI `.contextMenu` on the cell buttons.** On iOS that is the system long press with the
   cell lifted as preview; on tvOS a long press of the remote's select button, as in the channel
   list. The menu holds plain buttons; actions that need feedback put it where the screen shows
   it already: `model.notice` on the Apple TV, an alert on iPhone/iPad for a refused or failed
   server order (the sheet's inline text is not on screen with a menu).

3. **Menu contents** (only what applies, in this order):

   | | iPhone / iPad | Apple TV |
   |---|---|---|
   | running | Watch Channel | Watch Channel |
   | past, archive channel | Play from Start | Play from Start |
   | running / later, own recording | – | Record, or Stop Recording (running) / Don't Record (later) |
   | running / later, paired server | Record on Fernsy Server, or Cancel Recording | Record on Fernsy Server, or Remove from Server |
   | always | Details | Details |

   The server item's wording follows each platform's existing sheet or dialog ("Cancel
   Recording" on iPhone/iPad, "Remove from Server" on the Apple TV) so a show reads the same in
   menu and sheet. Details opens the existing sheet (iPhone/iPad) or dialog (Apple TV), whatever
   the show's time.

4. **Reuse the order and record paths.** iPhone/iPad call `model.orderOnServer` and
   `server.cancel` as `ServerRecordButton` does (moved into a small shared helper so the sheet
   and the menu say the same on failure); the Apple TV uses `model.schedule` (running and later),
   `recorder.stop` for a running recording and `recorder.unschedule` for a planned one, and
   `ServerDialogButtons` for the server. No new rule for the stream limit: the existing ones
   (server order that would start now, ask before taking a connection) apply.

5. **Server state in the menu.** Whether the server has an order comes from
   `server.order(channelId:start:)`, as in the sheet. The guide already refreshes the server's
   orders when it appears; the menu does not poll.

## Risks / Trade-offs

- [A long press on iOS can also start the scroll view's drag] → `.contextMenu` waits for the
  system long-press delay and cancels on movement, as in other scroll views; checked in the UI
  test on a cell inside the scrolled grid.
- [tvOS long press on a guide cell may fight with the guide's focus handling (rows keep focus
  while they load)] → the menu does not move focus; the existing focus test runs in the suite.
- [The server's order list may be stale when the menu opens] → "Record on Fernsy Server" on a
  show another device ordered meanwhile finds the existing order ("One server order per show")
  and shows it; no duplicate is written.

## Notes from implementing

- Task 1.4 runs as `GuideLongPressUITests.testRefusedWhileTheStreamIsInUse` (case d), but not
  with Picture in Picture: no simulator supports it, and on iPhone the guide is only on screen
  with playback going on in PiP. The stream is taken by the paired server's own running
  recording instead (`FernsyServer app-order 102 0 20`, `IPTV_MAXCONN=1`), which the same rule
  counts (`ServerModel.order`, unit test `orderThatStartsNowNeedsAFreeStream` covers this
  device's streams). The menu showed the refusal and the server kept its one order.
- The refusal's existing text (`ServerText.order`, shared with the sheet) says the streams are in
  use "on this device" also when the server's own recording uses them, and reads "1 stream(s)".
  Not changed here; worth a follow-up fix.
- iPhone tests (a)–(c) ran on the host against the local paired dev server; (b) fails with the
  menu's server item removed.
- Apple TV: the long-press menu's entries are cells holding their symbol (as in the channel
  list); the server's buttons (`ServerDialogButtons`, no symbol) are found by label. After the
  first menu closes, focus needs a moment to settle on the cell again; the tests wait for it
  before the next long press (a press too early opened the next show's menu).
- Task 2.3 checked the order path (`ServerUITests.testRunningShowOnTheServerFromTheMenu`,
  ordered, marked, taken back from the menu) against the local paired dev server; the
  stream-in-use refusal is the same `orderOnServer` path checked on iPhone (1.4) and shows as
  `model.notice` like the dialog's. `testServerOrdersAndSettings` needs an open order on the
  server (a fresh test server has none); with one it passes.
- The dialog's Record / Don't Record moved into `GuideRecordButtons`, shared with the menu; it
  now also offers Stop Recording for a show being recorded and nothing for a show that is over.
- Task 3.1 (2026-11-15, around 01:00): Apple TV UI tests on the host all pass, apart from a
  crash in `TrackPanelUITests` (2.6.2's test switch selected a fake track id and the session read
  past the stream list in `applyTrackChanges`; fixed in `PlaybackSession`, ids outside the
  container's streams are ignored) and one `SearchUITests` failure that passed on the rerun.
  iPhone: the VM run fails only playback tests (run on the host: pass) and
  `StartClockUITests.testLiveCardMovesOnToTheNextShow`, which fails on the host too and also on
  `main`'s code at that hour, so it is not this change's.
