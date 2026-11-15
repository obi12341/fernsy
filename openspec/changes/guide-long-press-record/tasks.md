# Tasks

## 1. iPhone and iPad

- [x] 1.1 Move the server order and cancel of `ServerRecordButton` into a small helper both the sheet and the menu use (order through `model.orderOnServer`, cancel through `server.cancel`, failure text through `ServerText.order(caught:)`), with no change to the sheet. Verify the existing `FernsyiOSUITests/ServerUITests.testGuideMarksAServerOrder` still passes against the local paired dev server (DEVELOPMENT.md › Fernsy Server; `TEST_RUNNER_IPTV_CONTROLKEY`, `TEST_RUNNER_IPTV_CONTROL`, `TEST_RUNNER_IPTV_CLOUD`, `TEST_RUNNER_IPTV_CLOUDTOKEN`) on the host.
- [x] 1.2 Add a `.contextMenu` to the show cells in `FernsyiOS/GuideView.swift` (design 3): Watch Channel (running), Play from Start (past, archive channel), Record on Fernsy Server or Cancel Recording (running and later, paired server), Details (opens `ShowDetailSheet` for any show); a refused or failed order shows an alert with the reason. German strings in the catalog ("Sender ansehen", "Von Anfang an", "Auf Fernsy Server aufnehmen", "Aufnahme abbrechen", "Details"). Verify the iOS app builds and, on the demo server without a server (`IPTV_LIVEVIEW=guide`), a long press on a running show of channel 101 shows Watch Channel and Details and no recording item (new UI test, task 1.3).
- [x] 1.3 Add `GuideLongPressUITests` to `FernsyiOSUITests` (demo server, `IPTV_LIVEVIEW=guide`, `IPTV_TAB=live`): (a) without a server the running show's menu has "Watch Channel" and "Details" only, and "Watch Channel" plays it; (b) with the paired dev server (skipped without it, as `ServerUITests`), long press on the running show of 101, "Record on Fernsy Server" → the cell's value becomes `server`; long press again offers "Cancel Recording", which removes the mark; (c) on a later show the menu's "Details" opens the sheet. Verify on the host (`scripts/ios-uitest.sh "-only-testing:Fernsy iOS UITests/GuideLongPressUITests"`) with and without the dev server, and that (b) fails with the menu's server item removed.
- [x] 1.4 Single-stream refusal from the menu: with the paired dev server and the demo account at one stream, play channel 101 (its stream counts in `tuners.connectionsInUse`; there is no switch to fake it), go back to the guide while it plays in Picture in Picture, and order the running show from the menu → the alert says the stream is in use and no order is written (`server.orders` unchanged in the log). Verify in the UI test of 1.3 as case (d), or record why it is checked by hand under "Notes from implementing" in design.md.

## 2. Apple TV

- [x] 2.1 Add a `.contextMenu` to the show cells in `FernsyTV/Screens/GuideScreen.swift` (design 3): Watch Channel / Play from Start, Record (`model.schedule`, notice into `model.notice`) or Stop Recording (`recorder.stop`, running) / Don't Record (`recorder.unschedule`, later), `ServerDialogButtons`, Details (opens the existing dialog for any show). German strings from the catalog ("Aufnehmen", "Aufnahme beenden", "Nicht aufnehmen", "Sender ansehen", "Details"). Verify the tvOS app builds and the existing `GuideUITests` and `GuideFocusUITests` pass on the host (`scripts/tv-uitest.sh`).
- [x] 2.2 Add `testRecordTheRunningShowFromTheGuide` to `FernsyTVUITests/GuideUITests` (demo server, `IPTV_FRESHRECORDINGS=1`): focus the running show of channel 101, long-press select (`XCUIRemote.press(.select, forDuration: 1.2)`), choose "Record" → the cell shows the recording mark and Recordings lists it as running; long-press again, "Stop Recording" → it is listed as done. Verify on the host and that it fails with the menu removed.
- [x] 2.3 With the paired dev server (skipped without it): long press on the running show, "Record on Fernsy Server" → the cell gets the server mark, or with the Apple TV playing the channel on the one-stream demo account the notice names the stream in use. Verify in `FernsyTVUITests/ServerUITests` on the host with the dev server running.

## 3. Integration

- [x] 3.1 Run the iPhone UI tests in the VM (`scripts/vm.sh scripts/ios-uitest.sh`, playback tests on the host), the Apple TV UI tests on the host, and `openspec validate --all --strict`. Verify all pass, apart from failures that also fail on `main`, which are named in design.md.
- [x] 3.2 Screenshots of the menus on the iPhone and the Apple TV simulator (German) for the user, attached from the UI tests (`shot(...)`), and a check on the user's real Apple TV with a Release build once they ask for it.

## Workflow follow-up

- Archive the change on `change/guide-long-press-record` after the checks, then merge into `main` and push when the user agrees.
- The user-visible commit carries `Release-Note-de` / `Release-Note-en` trailers (record a running show from the guide with a long press).
