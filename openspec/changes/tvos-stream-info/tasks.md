# Tasks

## 1. Shared rows

- [ ] 1.1 Add `StreamInfo` to `FernsyPlayer`: the Mac overlay's rows (labels and formatted values, including the playback method, timeshift buffer, reconnect and duplicate texts) from `PlayerStats` and the status, labels in the package's string catalog with German translations.
- [ ] 1.2 Make the Mac's `StatsOverlay` render `StreamInfo`; compare screenshots with `IPTV_SHOWINFO=1` on the demo server (live and a film) before and after; remove unused Mac strings.
- [ ] 1.3 Unit tests for `StreamInfo` in the package (row order, empty values as "–", duplicates and decode errors only when non-zero).

## 2. Apple TV

- [ ] 2.1 "Technische Infos" switch under Settings › Wiedergabe (`@AppStorage`, off by default), with German translation; `IPTV_SHOWINFO` turns it on in debug builds.
- [ ] 2.2 TV panel: `StreamInfo` rows and the two-minute buffer chart, TV sizes, top-right in the safe area, not focusable, no hit testing.
- [ ] 2.3 Show the panel in the live/timeshift player, the film/episode/Jellyfin player and the recording player while the switch is on.

## 3. Verification

- [ ] 3.1 UI test on the demo server: with `IPTV_SHOWINFO=1` the live player shows the panel and the overlay still opens with a click; without it no panel.
- [ ] 3.2 Simulator screenshots (`xcrun simctl io <id> screenshot`) of the panel in live, a film and a recording (demo server, `IPTV_TESTRECORD`), with and without the player overlay.
- [ ] 3.3 `scripts/test.sh` and `scripts/tv-uitest.sh` green.

## Workflow follow-up

- On the real Apple TV the user checks the panel with their provider (Release build).
- Archive with `/opsx:archive`, merge into `main`, push.
