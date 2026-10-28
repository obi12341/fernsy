# Tasks

## 1. Rows

- [x] 1.1 `StartRows` built once per catalog change: spotlight, film/series category rows, Jellyfin genre rows, best rated.
- [x] 1.2 Jetzt live and Heute Abend from favourites/recent/first channels, guide loaded for them.
- [x] 1.3 Spotlight as the large entry when nothing is to continue; Nächste Folge and Deine Aufnahmen rows.

## 2. Verification

- [x] 2.1 UI test (demo server): rows present without anything started, a live card plays its channel, a tonight show offers recording; existing Start tests still pass.
- [x] 2.2 Simulator screenshots of Start (demo; and with the user's large catalog without streams, no `IPTV_ALLOWREAL`) to check speed and look.
- [x] 2.3 German strings; `scripts/tv-uitest.sh` green.

## Workflow follow-up

- The user tries Start and decides on order and rows; archive afterwards.
