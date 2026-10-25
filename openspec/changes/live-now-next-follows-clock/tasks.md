# Tasks

## 1. Rows and pane follow the clock

- [x] 1.1 `NowNextLine` inside `TimelineView(.everyMinute)`, using `context.date` for the current show, the next show and the progress.
- [x] 1.2 `ChannelDetailPane` body inside `TimelineView(.everyMinute)`, using `context.date` for the current show, the remaining time, the following shows and their buttons.
- [x] 1.3 Debug switches, documented in the README:
  - `IPTV_CLOCKOFFSET=<s>` shifts "now" in rows and pane only;
  - `IPTV_EPGRECHECK=<s>` sets the check interval of visible rows;
  - `IPTV_EPGSTALE=1` makes `needsRefresh` true.

## 2. Visible rows keep their programme fresh

- [x] 2.1 Add `EPGStore.needsRefresh(_:)`, using the existing freshness rule.
- [x] 2.2 Turn `ChannelRow`'s task into a loop: load, then every 5 minutes reload when the programme needs a refresh. The task is cancelled when the row disappears.

## 3. Verification

- [ ] 3.1 On the demo server, set `IPTV_SCENE=live:<category>` and `IPTV_SELECT=<id>`, plus an `IPTV_CLOCKOFFSET` that puts the window about a minute before a show change in the demo EPG. Take screenshots of the Fernsy window before and after the change. Row and pane must show the new show, with the next show and progress moved on.
- [ ] 3.2 Check the reload with `IPTV_EPGRECHECK=<s>` (a shorter check interval) and `IPTV_EPGSTALE=1` (`needsRefresh` always true). The log for a visible row shows the programme being fetched again. Once the row disappears, it shows no more fetches.
- [x] 3.3 Debug and Release builds; `openspec validate live-now-next-follows-clock --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit and merge into main, only after the user agrees.
