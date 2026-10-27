# Tasks

## 1. Model

- [x] 1.1 `TVModel`: `liveSource` and `liveView` kept per account in UserDefaults, default Favoriten (Alle Sender without favourites), fallback when the stored category is gone or hidden; unit-testable rule in `FernsyCore` (`LiveRules`) with tests.
- [x] 1.2 Starting a channel from either view sets `zapSource` to `liveSource`.

## 2. Live TV screen

- [x] 2.1 Remove the Programm tab from `RootScreen`; keep the tab order otherwise.
- [x] 2.2 View switch "Liste | Programm" above the content as its own focus section, German strings.
- [x] 2.3 `CategoryColumn`: select on click only (drop `onChange(of: focused)`); focused and chosen looks stay distinct.
- [x] 2.4 Programm view: `GuideScreen` reads `liveSource`, its source menu goes; the column collapses to a rail with the source's name, clicking the rail expands it (design B), a click chooses and collapses, Right/Back collapses.
- [x] 2.5 "Alle Kategorien" from either view returns to that view with the clicked category.

## 3. Tests and verification

- [x] 3.1 Update `TabsUITests`, `GuideUITests`, `LiveTVUITests`, `AllCategoriesUITests` and tests that open Programm (search, recordings) for the switch.
- [x] 3.2 New UI tests (demo server): passing focus over the column does not change the rows; a category clicked in Liste shows in Programm; the rail opens the column, a click changes the guide; source and view kept after relaunch (`FERNSY_NO_KEYCHAIN` off for that test or a per-test defaults domain).
- [x] 3.3 Simulator screenshots of both views, the rail and the expanded column; rows, pane and grid compared with the Claude Design Live TV and guide screens (the switch and rail deviate by agreement, design E).
- [x] 3.4 Check with a large catalog (the user's provider, only while their Mac app plays nothing, or `IPTV_MAXCONN=1` with the demo server for the stream limit) that switching views and categories stays responsive.
- [x] 3.5 `scripts/test.sh` and `scripts/tv-uitest.sh` green.

## Workflow follow-up

- Archive with `/opsx:archive`, merge into `main`, push.
