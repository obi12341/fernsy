# Tasks

## 1. FFmpeg

- [x] 1.1 Enable the MPEG-TS muxer in `scripts/build-ffmpeg.sh` and rebuild Vendor/ffmpeg; verify BUILDINFO lists `--enable-muxer=mpegts` and no GPL flags
- [x] 1.2 Add muxer helpers to FFShim (`ffs_mux_*`) and verify the app builds

## 2. Tuner and buffer

- [x] 2.1 `ByteSource` protocol with HTTP, buffer and file sources; verify VOD still plays
- [x] 2.2 Tuner mode in `PlaybackSession`, `TimeshiftWriter`, `TimeshiftBuffer`, `LiveTuner`; verify live playback on the demo server (`IPTV_AUTOPLAY=live:101`)
- [x] 2.3 Buffer playback with index seeking; verify `IPTV_TESTSEEK=4`, `IPTV_TESTPAUSE=25:15`, `IPTV_TESTGOLIVE=55` give 0 rebuffers
- [x] 2.4 Continuous timeline across reconnects and clock jumps; verify the demo reconnect (~75 s) and `IPTV_TESTJUMP=25:-40` play through without rebuffer

## 3. Player UI

- [x] 3.1 Timeline, LIVE/TIMESHIFT state, ±10/60 s, back to live; verify screenshots of live, timeshifted and back-to-live states
- [x] 3.2 Stats overlay shows player + disk buffer and stored timeshift length

## 4. Connections and recordings

- [x] 4.1 `TunerPool` with limits and conflict prompts; verify with `IPTV_MAXCONN=1` and `IPTV_TESTRECORD=102:40:120` while 101 plays (prompt, auto-switch after 60 s)
- [x] 4.2 `Recorder`, `RecordingCopier`, files in ~/Movies/Fernsy; verify a 100 s recording spanning a reconnect probes with monotonic timestamps and no gaps
- [x] 4.3 Recordings section, record buttons in guide/channel list/player, settings; verify the recordings list screenshot and playback of a recording with seeking
- [x] 4.4 Quit confirmation with running/scheduled recordings

## 5. Menu bar

- [x] 5.1 Menu bar item and accessory mode without windows; verify `IPTV_TESTCLOSE=5` leaves the app running with activation policy accessory and no main-thread loop (`sample`)

## 6. Docs and localization

- [x] 6.1 English translations for all new strings (xcstringstool sync, no untranslated keys)
- [x] 6.2 README architecture note, store texts and What's New for 1.1 (`scripts/check-store-texts.py` passes)

## Workflow follow-up

- Manual checks still open: clicking through the conflict dialogs, the guide context menu, the quit dialog and the menu bar actions.
- Test once with the real provider when the user's own app is closed.
- Upload build 1.1 after the user approves.
