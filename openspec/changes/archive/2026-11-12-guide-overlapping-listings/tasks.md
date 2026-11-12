# Tasks

All app checks run against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
`IPTV_USER=demo`, `IPTV_PASS=demo`) with `IPTV_TESTEPGOVERLAP=101` (channel 101 gets overlapping
listings). No stream is needed for any of them. Package and simulator tests run in the VM
(`scripts/vm.sh`), the Mac builds on the host and runs as Fernsy Dev, never the user's app.

## 1. The rule

- [x] 1.1 Resolve overlaps in `EPGStore.clean` (design 2 to 5): earliest end first on the whole list, two minutes of tolerance with the earlier listing's end moved, then the cut to the kept range, result sorted by start; the "same start only once" step goes. Verify: new `EPGOverlapTests` in FernsyCore cover two versions of a schedule, a placeholder across real shows, the same show with starts seconds apart, two listings with the same start, a one-minute overlap (both kept, first one shortened), a three-minute overlap (one dropped), an already resolved list coming back unchanged, and the selection staying the same when `now` moves so that the winner of an overlap leaves the kept range; `EPGKeptRangeTests` still pass (`scripts/vm.sh scripts/test.sh`). Done 12 Nov: `EPGOverlapTests` (10 tests) and `EPGKeptRangeTests` pass in the VM, and so does the whole `scripts/test.sh`.
- [x] 1.2 `nowAndNext` on a programme with a second listing of the running show. Verify: a test in `EPGOverlapTests` loads such a list through `clean` and expects the show after the running one as next. Done 12 Nov: `nextIsNotTheRunningShowsSecondListing` (the lookup moved into a static `nowAndNext(in:at:)` so it can be tested on a list).
- [x] 1.3 Say how many listings were dropped for overlapping in the detail log line of a downloaded table (design 6). Verify: the line shows in the log of the run of 2.2. Done 12 Nov: "channel 101: 319 entries, 159 kept, 160 overlapping dropped" (Fernsy Dev), read by the UI test of 2.2.
- [x] 1.4 Sample test: a test that runs `clean` over every programme file in the directory named by `FERNSY_EPG_SAMPLE` (cache format; skipped when the variable is unset) and expects no overlaps, reporting listings dropped and minutes left uncovered. Verify: run once with a copy of the listings from the Mac app's guide cache (read-only copy kept outside the repo); record the numbers next to the exploration's (46 dropped, 0 minutes) under "Notes from implementing" in design.md. Done 12 Nov with `TEST_RUNNER_FERNSY_EPG_SAMPLE` in the VM (copy in the git-ignored `build/`, titles and times only): 118 channels, 7533 listings, 12 channels with overlaps, 46 dropped, 1 minute left uncovered.

## 2. Debug switch and the apps

- [x] 2.1 `IPTV_TESTEPGOVERLAP=<channel id>` in debug builds (design 6): a second version of each listing ten minutes later and a placeholder across the shows around now, added before cleaning, disk cache skipped for that channel; documented with the other guide switches in DEVELOPMENT.md. Verify: a unit test shows that the added listings overlap before `clean` and none do after. Done 12 Nov: `debugListingsOverlap`.
- [x] 2.2 iPhone UI test `GuideOverlapUITests.testOverlappingListingsShowSeparateCells`: demo server with `IPTV_TESTEPGOVERLAP=101`, the guide open; the frames of the cells `guide.101.*` do not intersect, and the log has the line of 1.3 with a count above zero for channel 101. Verify: `scripts/vm.sh scripts/ios-uitest.sh "-only-testing:Fernsy iOS UITests/GuideOverlapUITests"` passes, and fails when the rule is switched off locally (checked once, not committed). Done 12 Nov: passes on the iPhone 18 Pro and iPad Pro 11-inch simulators; with the rule switched off it failed ("317 entries, 317 kept, 0 overlapping dropped").
- [x] 2.3 Mac and Apple TV by eye: Fernsy Dev (`scripts/dev-run.sh` with `IPTV_TESTEPGOVERLAP=101`, `IPTV_SECTION=live`, `IPTV_LIVEMODE=guide`) and the Apple TV app in the tvOS simulator with the same variable (`IPTV_TAB=live`, `IPTV_LIVEVIEW=guide`). Verify: screenshots of both guides show channel 101's row with separate, readable cells, and the Mac's channel list (`IPTV_LIVEMODE=list`) names the show after the running one as next. Done 12 Nov: both guides show 101's row as consecutive cells without the placeholder; the Mac's list has "Next 18:30" for the show running 17:45–18:30 (the demo channel repeats one title, so the start time tells it, not the title).

## 3. Integration

- [x] 3.1 Everything together. Verify: `scripts/vm.sh scripts/test.sh` passes; the guide UI tests pass (`scripts/vm.sh scripts/ios-uitest.sh "-only-testing:Fernsy iOS UITests/GuideSourceSwitchUITests"`, `scripts/vm.sh scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/GuideFocusUITests" "-only-testing:Fernsy TV UITests/GuideEmptyChannelsUITests"`); the Mac, Apple TV and iOS targets build; `openspec validate --all --strict` passes. Done 12 Nov: `scripts/test.sh`, `GuideSourceSwitchUITests` (iPhone), `GuideFocusUITests`, `GuideUITests` and `LiveAndGuideUITests` (Apple TV) pass in the VM; `GuideEmptyChannelsUITests` ends by playing a channel, which the VM cannot ("channel 102 does not play"), and passes on the host; all three targets build; validation passes. Not a pass: the iPad's `testGuideScrollsSmoothly` is over its late-frame limit in the VM, with and without this branch's code (design.md, "Notes from implementing").

## Workflow follow-up

- The commit that brings the rule carries `Release-Note-de` / `Release-Note-en` (overlapping listings no longer sit on top of each other in the guide).
- Archive on `change/guide-overlapping-listings`, then merge into `main` and push when the user agrees.
