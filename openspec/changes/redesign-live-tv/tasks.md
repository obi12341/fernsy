# Tasks

## 1. Rows

- [x] 1.1 `ChannelRow` at 58 pt: number, logo tile, tagged name, marks (StatusBadge playing/REC/Offline/Ausgeblendet, star), a now line with "Danach HH:MM title", and a progress bar (red while recording). Lazy EPG load per row. Verify: demo list screenshot shows now/next and progress per row.
- [x] 1.2 `AppModel.offlineChannels` from offline playback failures (cleared on success), shown in rows. Verify: `IPTV_TESTNODATA=offline:600` with `IPTV_AUTOPLAY=live:101` marks row 101 "Offline".

## 2. Detail pane

- [x] 2.1 `ChannelDetailPane` (316 pt) right of the list from 720 pt width, below it when narrower. Header, Einschalten, favourite, ⋯ menu, JETZT card with remaining minutes and Aufnehmen, DANACH list (4) with Aufnehmen/Geplant capsules, and "Kein Sender ausgewählt". Verify: `IPTV_SELECT=101` screenshot. Scheduling a later show switches its capsule to "Geplant" (`IPTV_TESTSCHEDULE` = schedule the 2nd upcoming show of the selected channel).

## 3. Context menu, shortcuts, Edit mode

- [x] 3.1 Context menu entries in the order of design §4, with ⌘D and ⌘I on the selection. "Im Programm zeigen" switches to the guide. Verify: build. The ⋯ menu in the pane uses the same `ChannelMenu`. Opening menus needs input events, so the user checks the menu by hand.
- [x] 3.2 Edit mode: checkboxes instead of eyes, dimmed hidden rows with the "Ausgeblendet" badge, "Alle einblenden" in the toolbar, the explanatory note, and adult categories locked with the footer note. Verify: `IPTV_SCENE=live:<cat>:edit` screenshot.

## 4. States

- [x] 4.1 Loading placeholder rows with a card, empty favourites view with "Alle Sender anzeigen", and the provider-unreachable banner with Retry. Verify: screenshots for the empty favourites (`IPTV_SCENE=live:__favorites`) and the banner (debug `IPTV_TESTCATALOGFAIL=1` makes the refresh fail while the cache is shown).

## 5. Localization and verification

- [x] 5.1 New strings in `Localizable.xcstrings` (de + en), with no stale keys. README lists new debug switches. Verify: build.
- [x] 5.2 Debug and Release builds compile. `openspec validate redesign-live-tv --strict` and `openspec validate --specs --strict` pass. Screenshots in dark and light (`IPTV_APPEARANCE`).

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
