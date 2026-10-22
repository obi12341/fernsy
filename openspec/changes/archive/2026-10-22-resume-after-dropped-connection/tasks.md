# Tasks

## 1. Reproduce

- [x] 1.1 `IPTV_TESTNET` kind `close:<s>` (clean server close of the current download); verify on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUTOPLAY=movie:500`, `IPTV_TESTPAUSE=10:20`, `IPTV_TESTNET=close:15`) that the build before the fix ends the film early (status ended after the buffer) — the demo films are one 51 s clip that fits the buffer, so the test used a local range server (scratchpad, 3 MB/s) with a 5-minute, 500 MB file via `IPTV_PLAYURL`: `IPTV_TESTPAUSE=5:15 IPTV_TESTNET=close:8` ended at 28 s of 299.5 s (reproduced); `IPTV_TESTNET` now also runs for films

## 2. Continue the download (A)

- [x] 2.1 `HTTPByteSource.continueDownload()`: on early completion (clean or error, not cancelled) with `supportsRanges`, request `bytes=<bufferEnd>-` keeping the buffer; accept only 206 starting at `bufferEnd`; up to 5 attempts with back-off; otherwise a failure, never EOF; verify the same demo run plays on past the buffer (log shows the continue, position keeps rising, no end), and with `IPTV_TESTNET=drop:15` while playing — same local setup: close during the pause → "continuing" at 237 of 500 MB, played on past 195 s; `drop:8` while playing → continued at 114 MB, kept playing

## 3. Plausible end (B)

- [x] 3.1 `PlayerEngine`: `.ended` more than 60 s before a known duration → reload at the position once (or `restartAt` for transcodes), then `.failed`; verify by forcing an early EOF with a debug switch that disables A (`IPTV_TESTNOCONTINUE=1`): the film reloads at its position instead of "Play Again"
- [x] 3.2 Jellyfin: verify with a Jellyfin film (direct play, `JF_AUTOPLAY` + `IPTV_TESTNET=close:15`, `FERNSY_NO_KEYCHAIN=1`, debug device) that playback continues and, after closing, the server keeps it as partly watched at the stop position; back up and restore the film's user data

## 4. Finish

- [x] 4.1 Regression: demo live channel (`IPTV_AUTOPLAY=live:101`, `IPTV_TESTNET=drop:15`) reconnects as before; a demo film played to its real end still shows "ended"; README (debug switches) and translations
- [x] 4.2 Restore Jellyfin test data, remove the debug device only, delete credentials, verify nothing secret in the repository or logs

## Workflow follow-up

- Archive after the user's review, then merge `change/resume-after-dropped-connection` into `main` with the user's OK.
