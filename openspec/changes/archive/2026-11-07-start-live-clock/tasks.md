# Tasks

## 1. Mac

- [x] 1.1 `StartLiveCard` in `TimelineView(LiveClock.everyMinute)`, "now" from `LiveClock.now(context.date)`
- [x] 1.2 Start's guide task: `epg.keepFresh` per live channel (task group, cancelled with Start); `rows.tonight` recomputed each full minute and after guides arrive

## 2. Apple TV and iPhone/iPad

- [x] 2.1 `LiveClock` for tvOS/iOS in `FernsyTV/Support/LiveClock.swift` (seconds-based minute schedule, `IPTV_CLOCKOFFSET` in debug builds); the synced FernsyTV folder puts it into both targets
- [x] 2.2 Apple TV `StartLiveCard` and iOS `LiveCard` in the minute timeline (show, progress, time left from the clock); `currentShow(on:at:)` with the clock's date
- [x] 2.3 Apple TV and iOS Start: guides through `keepFresh`, `rows.tonight` per minute as on the Mac

## 3. Verification

- [x] 3.1 Apple TV UI test `StartClockUITests` on the demo server (with `IPTV_EPGSTALE=1`): it reads the next title change on channel 101 from the demo server, sets `IPTV_CLOCKOFFSET` 60 s before it, and the `start.live.101` card's value changes to the next show without leaving Start (the card exposes the show title as its accessibility value; the button joins its texts, so the test checks that the value contains the title)
- [x] 3.2 iOS: `StartClockUITests` (Fernsy iOS UITests) passes on the iOS simulator. Mac: Fernsy Dev with `IPTV_FAVORITES=live:101 IPTV_CLOCKOFFSET=<60 s before a change>`: the log line `[test] start live 101` goes from "Evening Gala" to "Cooking with Friends" 94 s after launch, without leaving Start (the Mac's minute schedule ticks on the real minute, so within a minute of the change)
- [x] 3.3 `scripts/vm.sh scripts/test.sh` green; the Apple TV UI suite (`--parallel 3`) green except `StartClockUITests`, which failed with a guide cached on the simulator from an earlier day and passes with `IPTV_EPGSTALE=1` (alone, with a 5 h clock offset); the iOS build and `StartClockUITests` on iOS green

## 4. Wrap-up

- [x] 4.1 DEVELOPMENT.md (`IPTV_CLOCKOFFSET` on Apple TV/iOS, Start follows the clock), pitfall in design.md if any; `openspec validate --all --strict`; archive, merge into `main`, push (with the user's consent)
