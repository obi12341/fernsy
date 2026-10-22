# Tasks

## 1. Reproduce

- [x] 1.1 Debug switch `IPTV_TESTSWITCH=<s>:<live|movie>:<id>` that starts an item through the same `AppModel` entry point as the main window; reproduce on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUTOPLAY=live:101`, `IPTV_TESTPIP=3`, `IPTV_TESTSWITCH=8:live:102`) that the player window pops up and the PiP picture freezes (screenshot of the PiP window region only, debug log) – the pop-up reproduced; the "frozen" picture turned out to be the old channel's last frame during loading (user's test), see design.md

## 2. Switching while PiP runs

- [x] 2.1 `AppModel.isPictureInPictureActive` set by the player; `LibraryView` does not open the player window while it is true; verify with the run from 1.1 (window list: player window stays hidden)
- [x] 2.2 Find and fix the frozen PiP picture (record cause and fix in design.md); verify with `IPTV_TESTSWITCH=8:live:102` and `IPTV_TESTSWITCH=8:movie:500` that the PiP window shows the new item (PiP region screenshots before/after) with matching controls (live vs. progress bar), and `IPTV_TESTPIP=3:back:9` that "back" shows the player window with the new item – controls follow via `invalidatePlaybackState()` on the media change, not checked by hovering (no mouse input on the user's screen)
- [x] 2.4 Loading picture in PiP while a new item loads (`PictureInPictureLoadingCard`, session hook before the first video frame); verify on the demo server with `IPTV_TESTSWITCH=8:live:102` (PiP region screenshots during loading and after the first picture, debug log of card start/stop) and with `IPTV_TESTNET=stall:…` or a slow start if needed to see the card longer
- [x] 2.3 Item without video while PiP runs ends PiP with "back"; verify on the demo server with a channel without video if the demo offers one, otherwise by forcing `hasVideo == false` in a debug run, and say which was used – forced with `IPTV_TESTNOVIDEO=1` (the demo has no radio channel)

## 3. Finish

- [x] 3.1 README (`IPTV_TESTSWITCH`, `IPTV_TESTSLOWSTART`, `IPTV_TESTNOVIDEO`); regression: PiP start/back with `IPTV_TESTPIP=4:back:4` (player window shows the picture again) and PiP not starting before the first frame (`IPTV_TESTSLOWSTART=4`, no crash); close via the PiP window and resizing were not re-run (they need mouse input on the user's screen; code paths unchanged); `openspec validate --all --strict`

## Workflow follow-up

- Archive after the user's review, then merge `change/keep-picture-in-picture-on-switch` into `main` with the user's OK.
