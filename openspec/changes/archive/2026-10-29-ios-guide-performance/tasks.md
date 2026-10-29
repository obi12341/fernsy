# Tasks

## 1. Before

- [x] 1.1 Add the guide scrolling UI test (iPad simulator, demo server via `IPTV_SERVER` demo as in the existing tests, `IPTV_FRAMESTATS=1`): open Programm, swipe down/up and back in time, collect "frames:" lines and the number of rows built (a DEBUG log line when a guide row appears). Run it on the current code and note late frames and rows built as the before numbers. Before (iPad Pro 13-inch simulator, landscape): all 24 rows built at open, 50 late frames in 33 s of scrolling, longest frame 767 ms.

## 2. Guide layout

- [x] 2.1 Rebuild `GuideView` as a horizontal `ScrollView` around a vertical one with a `LazyVStack` of rows and the hour bar as pinned section header (design 1; a single two-axis scroll view was not lazy).
- [x] 2.2 Keep the channel column at the left: logo cell per row and the header corner shifted by the horizontal offset from `onScrollGeometryChange`, above the shows.
- [x] 2.3 Pass the visible span (hours, one viewport margin each side) to the rows; rows draw only shows and gaps in it (design 2).
- [x] 2.4 `loadGuide` per appearing row; `loadPast` keyed on the visible span's start day, only when it reaches more than three hours back (design 3).
- [x] 2.5 Open half an hour before now; now line, dimming, highlight, tap rules and gap bars as before.

## 3. Verify

- [x] 3.1 The new test passes on the iPad simulator; note late frames and rows built against 1.1. With 400 channels (`IPTV_TESTBIGLIVE=400`): before all 400 rows built and two freezes of about 9.8 s; after 29 rows at open, 68 after scrolling, no freeze, 90 late frames in 33 s, longest frame 465 ms (an XCTest drag, design 5).
- [x] 3.2 All iPhone and iPad UI tests pass (`scripts/ios-uitest.sh`).
- [x] 3.3 If late frames stay high, report and decide with the user on the `UICollectionView` fallback (design 1) before going on. Not needed: the user found the guide fluid on the iPad.
- [x] 3.4 On the user's iPad (Release build per the ipad-release recipe, real channel list, listings only): open Programm, scroll up, down and back days; the user confirms it is fluid. The app log shows guide requests only for channels scrolled past. The Release log does not record guide requests per channel; that rows load only when they appear is shown in the simulator instead (3.1: 68 of 400 rows built, each row loads its listings on appearing). The user: "ist deutlich besser, fühlt sich flüssig an".
- [x] 3.5 `openspec validate --all --strict` passes.
