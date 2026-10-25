# Tasks

## 1. Panel

- [x] 1.1 Add `Fernsy/Views/PlayerChannelList.swift` with:
  - the panel (material, 340 pt, at most 45 % of the width, slides in from the left);
  - the category menu (Favoriten, Zuletzt gesehen, categories);
  - a `List` of `PlayerChannelRow`s (number, logo, tagged name, current show with progress, marks), using a minute clock;
  - scrolled to the channel playing, with the highlight.
- [x] 1.2 Rows load their programme like `ChannelRow`. If `live-now-next-follows-clock` is already on main, reuse its clock and refresh loop.

## 2. Player integration

- [x] 2.1 Wiring in `PlayerScreen`:
  - `showsChannelList` state;
  - a button "Senderliste (L)" in `PlayerControls` for live TV only;
  - the panel kept clear of the control panel;
  - the zap banner moved beside the panel while it is open.
- [x] 2.2 Keyboard: while the list is open, ↑/↓, Page Up/Down and Return act on the list, and L/Esc close it (Esc closes the list before leaving full screen). L toggles the list for live TV only.
- [x] 2.3 Tuning from the list: click or Return → `app.play(channel)` with the banner, and the existing question when a recording holds the connection. The list stays open, and its highlight follows the playing channel.
- [x] 2.4 Closing by a click on the picture and after 10 s without interaction with the list. Tuning restarts the timer.

## 3. Verification (demo server, player window screenshots only)

- [x] 3.1 `IPTV_AUTOPLAY=live:<id>` with `IPTV_TESTCHANNELLIST=5`: screenshot of the open list, scrolled to the playing channel with its mark, current shows and progress. Check it in light and dark (`IPTV_APPEARANCE`) and in a narrow window (`IPTV_WINDOW=800x500`).
- [x] 3.2 `IPTV_TESTCHANNELLIST=5:down,down,return`: the log shows the highlight moving without tuning, then the tune on Return; the list stays open, and a screenshot is taken.
- [x] 3.3 Run with `IPTV_TESTCHANNELLIST=5` and no further keys; the log or a screenshot shows the list closed after 10 s.
- [x] 3.4 Pick a channel from favourites (`IPTV_FAVORITES=live:103,live:110`, held in memory only, and `IPTV_TESTCHANNELLIST=5:category:__favorites,down,return,esc`), then zap with ↓ via `IPTV_TESTZAP`. The log shows the next channel of that channel's own category.
- [x] 3.5 With a film (`IPTV_AUTOPLAY=movie:500`), L and the button do nothing.

## 4. Localization and verification

- [x] 4.1 Strings (de + en) without stale keys; README switch `IPTV_TESTCHANNELLIST`.
- [x] 4.2 Debug and Release builds; `openspec validate player-channel-list --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit and merge into main, only after the user agrees.
