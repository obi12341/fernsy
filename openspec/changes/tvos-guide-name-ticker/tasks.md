# Tasks

All app checks run against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
`IPTV_USER=demo`, `IPTV_PASS=demo`) in the tvOS simulator; no stream is needed. Channel 101
(shown as "Northern Light 1") has a name that does not fit the guide's channel column, channel 104
("Current TV") has one that fits. Package tests and the Apple TV UI tests run in the VM
(`scripts/vm.sh`); the simulator for looking at the result runs on the host with its window.

## 1. The motion

- [x] 1.1 The ticker's offset as a pure function in FernsyCore (design 2): elapsed time, distance, speed (40 points per second) and rest (1 s) give the offset; rest at the beginning, slide to the end, rest, slide back, repeat. Verify: new unit tests in FernsyCore cover the first rest (offset 0), the middle of the first pass, the rest at the end (offset equals the distance), the way back, the second loop being the same as the first, and a distance of zero or less (always 0); `scripts/vm.sh scripts/test.sh` passes. Done 12 Nov: `TickerMotionTests` (8 tests); `scripts/vm.sh scripts/test.sh` passes.

## 2. The guide

- [x] 2.1 The moving text view in `FernsyTV/Support` (design 3, 4): not active, Reduce Motion (or `IPTV_TESTREDUCEMOTION=1` in debug builds) or a text that fits give today's `Text` with `lineLimit(1)`; otherwise the full-width text, clipped, faded at an edge where it continues, offset by 1.1 on a 30-per-second clock. It measures only while active. Verify: the Apple TV target builds, and the view is used by 2.2's test. Done 12 Nov: `FernsyTV/Support/TickerText.swift`; the Apple TV target builds and both tests of 2.2 and 2.3 use it.
- [x] 2.2 Use it for the channel name in `GuideRow`, active while a cell of the row has focus (design 1), with the identifier `guide.name.<channel id>`, the full name as accessibility label, the value "moving" while it slides, and a detail log line per start (design 5). Verify with the new UI test `GuideNameTickerUITests` (demo server, `IPTV_FRAMESTATS=1`, guide view): with focus in row 101 the name's value becomes "moving" and two screenshots of the name taken 1.5 s apart differ; after Right to the next cell of the same row the log still has one "name ticker started" line for row 101; after Down the value of 101's name is empty again; with focus in row 104 its value stays empty for 3 s; the late-frame lines logged while the name moves are attached. `scripts/vm.sh scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/GuideNameTickerUITests"` passes. Done 12 Nov: passes in the VM and on the host. Instead of two screenshots the test takes eight over eight seconds (more than one loop) and expects more than two different looks of the name; the late frames are attached for the moving name and, from 2.3, for the resting one.
- [x] 2.3 Reduce Motion: `IPTV_TESTREDUCEMOTION=1` in debug builds (design 5), documented with the Apple TV switches in DEVELOPMENT.md. Verify: a second test in `GuideNameTickerUITests` launches with it, puts focus in row 101 and finds the name's value empty for 3 s. Done 12 Nov: `testReduceMotionKeepsTheNameShortened` passes in the VM and on the host; it also expects the name to look the same in eight screenshots.
- [x] 2.4 Look at it: the Apple TV app in the tvOS simulator on the host (`IPTV_TAB=live`, `IPTV_LIVEVIEW=guide`). Verify: screenshots taken while focus is in row 101, at rest in the first second, mid-slide and at the end, show the name's beginning, a middle part with faded edges and its end ("… Light 1") next to the archive mark, with nothing drawn over the logo or the first cell; a screenshot after Down shows the shortened name ("Northern…") again. Done 12 Nov, from the screenshots the UI test attaches on the host: "Northern L" faded on the right, "thern Light" faded on both sides, "ern Light 1" faded on the left, each between the logo and the archive mark; after Down and with reduced motion "Northern…".

## 3. Integration

- [x] 3.1 Everything together. Verify: `scripts/vm.sh scripts/test.sh` passes; the guide's UI tests pass (`scripts/vm.sh scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/GuideNameTickerUITests" "-only-testing:Fernsy TV UITests/GuideFocusUITests" "-only-testing:Fernsy TV UITests/GuideUITests" "-only-testing:Fernsy TV UITests/LiveAndGuideUITests"`; `GuideEmptyChannelsUITests` plays a channel and runs on the host, `scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/GuideEmptyChannelsUITests"`); the Mac, Apple TV and iOS targets build; `openspec validate --all --strict` passes. Done 12 Nov: `scripts/test.sh` and the four guide classes plus `AllCategoriesUITests` pass in the VM, `GuideEmptyChannelsUITests` on the host; the Mac, Apple TV and iOS targets build; validation passes.

## Workflow follow-up

- The commit that brings the moving name carries `Release-Note-de` / `Release-Note-en` (long channel names in the Apple TV guide can be read in full while their row has focus).
- Archive on `change/tvos-guide-name-ticker`, then merge into `main` and push when the user agrees.
