# Tasks

## 1. Model

- [x] 1.1 `AppModel`: add `isAdult(_ channel:)` (provider flag or adult category). Use it in `filteredChannels` for the existing `showAdult` filter.
- [x] 1.2 `AppModel`: add a published `showAdultInRecent` (UserDefaults `library.showAdultInRecent`, default off). `filteredChannels` drops adult channels from `recentChannelsID` while it is off.
- [x] 1.3 `AppModel.removeRecent(_:)`: removes the id from `recentChannels` and saves it like `noteRecent` (not in test runs).
- [x] 1.4 Debug switches in `debugBootstrap`, all in memory and never written to UserDefaults, documented in the README:
  - `IPTV_TESTADULT=<id,…>` treats channels as adult;
  - `IPTV_RECENT=<id,…>` sets the history;
  - `IPTV_SHOWADULT=0|1` and `IPTV_ADULTRECENT=0|1` set both settings.

## 2. UI

- [x] 2.1 `YouthProtectionSettings`: toggle "Erwachsenen-Sender unter „Zuletzt gesehen“ anzeigen" below the existing one, disabled while adult categories are hidden, with a footer line.
- [x] 2.2 `ChannelMenu`: "Aus „Zuletzt gesehen“ entfernen" after the favourites item, only while the channel is in the history.
- [x] 2.3 Strings (de + en) without stale keys.

## 3. Verification (demo server)

- [ ] 3.1 Hide by default. Run with `IPTV_TESTADULT=103`, `IPTV_RECENT=101,103,102`, `IPTV_SHOWADULT=1` and `IPTV_SCENE=live:__recent`. Screenshot: "Zuletzt gesehen" lists 101 and 102, not 103, and the count says 2.
- [ ] 3.2 Show again. Same run with `IPTV_ADULTRECENT=1`. Screenshot: 101, 103, 102 in that order, count 3.
- [ ] 3.3 Adult categories off. Run with `IPTV_SHOWADULT=0` and `IPTV_ADULTRECENT=1`, `IPTV_TESTSETTINGS=youthProtection` (opens Settings › Jugendschutz). Screenshot: the new toggle is disabled, and 103 is not in "Zuletzt gesehen".
- [ ] 3.4 Removal. Run with `IPTV_RECENT=101,102` and a debug trigger `IPTV_TESTUNRECENT=101` that calls `removeRecent` after the list is shown, the same path as the menu item. Screenshot: only 102 is left. The installed app's `live.recent` default is unchanged (`defaults read` before and after).
- [x] 3.5 Debug and Release builds; `openspec validate recent-channels-adult-and-remove --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees. The menu item itself is checked by the user (no mouse injection).
