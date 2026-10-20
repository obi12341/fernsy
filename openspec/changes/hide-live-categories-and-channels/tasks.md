# Tasks

## 1. Visibility model

- [x] 1.1 Add `ChannelVisibility` (Codable, per account `visibility.json`), load on sign-in, keep across catalog refreshes; verify with the demo account that hidden ids survive a relaunch (`IPTV_SERVER=… demo/demo`) and a different account starts empty
- [x] 1.2 `isHidden`, `filteredChannels(includeHidden:)`, visible category counts; verify hiding a demo category removes its channels from "All" and lowers the count

## 2. Zapping and favorites

- [x] 2.1 Exclude hidden channels from `zapList`, step past them in `neighbor` (also when the current channel is hidden); verify with a debug run zapping ↓ over two hidden demo channels (`IPTV_TESTZAP` on channel 101 with 102/103 hidden)
- [x] 2.2 Exclude hidden channels from Favorites; verify a hidden favorite disappears and returns when shown

## 3. UI

- [ ] 3.1 Context menu "Hide" in category column, channel list and guide channel column; verify each in the demo catalog
- [x] 3.2 Edit mode (toolbar Edit/Done, dimmed hidden rows with eye toggle, switch from guide to list); verify by screenshot of Edit mode with one hidden category and channel
- [x] 3.3 Translate new strings (xcstringstool sync, no untranslated keys)

## 4. Integration

- [x] 4.1 Hide the playing channel and verify playback and a running recording continue (demo server)

## Workflow follow-up

- Archive the change after review.
- iCloud sync of `ChannelVisibility` as a later change.
