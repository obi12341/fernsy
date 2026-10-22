# Tasks

## 1. PiP on the display layer

- [x] 1.1 `PictureInPicture` with an `AVPictureInPictureController` on `engine.displayLayer` and the playback delegate (play/pause, time range, live as infinite, skip via seek); verify on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUTOPLAY=movie:500`, `IPTV_TESTPIP=4`) that PiP starts and shows the film (screen screenshot)
- [x] 1.2 Work around the unscaled PiP mirror (`PictureInPictureStage`: layer in an invisible window at the PiP window's size, stale overlay hidden, flush on return); measured: letterbox bars symmetric (102/640/102 px at 750×422), live 16:9 fills the PiP window at 949×534 and after shrinking to 551×309

## 2. Player window and controls

- [x] 2.1 PiP button in the controls (hidden when not possible) and key P; player window hidden on start, shown again on "back", playback stopped on close; verify with `IPTV_TESTPIP=4:back:4` (window back with picture, position continued) and the PiP window's close button (playback stopped, window closed) on the demo server
- [x] 2.2 Live and on-demand in PiP: verify on the demo server that live TV shows as live and pausing continues time-shifted, a film skips ±10 s (system interval), pause/play work (screenshots / debug log)

## 3. Finish

- [x] 3.1 Translations (xcstringstool sync, no untranslated keys), README note (PiP, subtitles not in PiP, `IPTV_TESTPIP`); `openspec validate --all --strict`; manual check by the user (PiP, resize, back, close via X). Closing the player window without PiP was not re-tested: that code path is unchanged

## Workflow follow-up

- Archive after the user's review, then merge `change/add-picture-in-picture` into `main` with the user's OK.
