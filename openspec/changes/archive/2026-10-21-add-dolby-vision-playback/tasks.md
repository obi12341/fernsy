# Tasks

## 1. Setup

- [x] 1.1 Pick test items from the Jellyfin library (DV P5 film, DV P8.1 episode, DV P8 + HDR10+ film, DV P7 film, an HDR10 film without DV) and back up their complete user data; verify the backup lists every test item

## 2. Dolby Vision decoding

- [x] 2.1 Shim helpers: read the stream's DOVI config record (profile, level, flags, compatibility id) and serialise it as a 24-byte `dvcC`; tell whether the extradata is an `hvcC`
- [x] 2.2 `DVDecoder`: `dvh1` format description (`hvcC` + `dvcC`), sample buffers over packet data, synchronous decode, reorder queue by PTS, flush; pixel buffers keep their DV attachments
- [x] 2.3 `videoMain` chooses `DVDecoder` for HEVC profile 5/8 with `hvcC` extradata when `VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC)`; profile 7, MPEG-TS and unsupported Macs keep the FFmpeg path; verify with `JF_AUTOPLAY=<P5 film>:900` + `IPTV_SHOWINFO=1` that the colours are right (screenshot) and the overlay shows "Dolby Vision 5" and "VideoToolbox (Dolby Vision)"
- [x] 2.4 Fallback: session creation or first-frame failure → profile 8 reopens with the FFmpeg decoder, profile 5 fails before start with a clear message; verify with a debug switch that disables the DV path (`JF_NODV=1`) that P8 plays as HDR10 and a Jellyfin P5 item switches to a transcode — verified with `JF_NODV=1` (P8.1 → "Dolby Vision 8.1 → HDR10 (PQ)", P5 → transcode); a session that fails only at the first frame could not be provoked on this Mac, that path is covered by code review only
- [x] 2.5 Seeking, pause, preroll and frame order: verify on the P8.1 episode with `IPTV_TESTSEEK=1800` (lands at 30:00, no stutter, debug log shows PTS in order, 0 dropped frames) and on the P5 film with `IPTV_TESTPAUSE=10:5`
- [x] 2.6 Subtitles and stats on DV: verify PGS/SRT subtitles on the P8 film (`IPTV_TESTSUB`) and that the info overlay names profile and path; P7 film shows "Dolby Vision 7.6 → HDR10 (PQ)" and plays as before

## 3. Jellyfin

- [x] 3.1 `transcodeReason` no longer transcodes P5 when the Mac decodes DV; verify the P5 film plays directly (server session: DirectPlay, no transcode) and with `JF_NODV=1` it is transcoded as before

## 4. Regression

- [x] 4.1 Non-DV playback unchanged: HDR10 film from Jellyfin (`JF_AUTOPLAY`) and a demo-server film and live channel (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUTOPLAY=movie:<id>` and `live:<id>`) play as before with the same decoder and dynamic range in the overlay

## 5. Audio fix (found during testing)

- [x] 5.0 TrueHD was silent: collect decoded audio into ≥ 20 ms blocks and follow the sample count for millisecond-rounded timestamps; verified by ear on Apocalypse Now (TrueHD 5.1, seek, switch to AC-3 and back) and Alles steht Kopf 2 (TrueHD 7.1), regression on demo-server film and live channel (AAC) with `IPTV_AUDIOLEVEL=1`

## 6. Finish

- [x] 6.1 Translations (xcstringstool sync, no untranslated keys), README note on Dolby Vision playback and the `JF_NODV` switch
- [x] 6.2 Restore the backed-up user data of all test items and verify it matches the backup; log out test sessions, remove credentials and verify no host, user or token is in the repository or logs

## Workflow follow-up

- Archive after the user's review, then merge `change/add-jellyfin-playback` and `change/add-dolby-vision-playback` into `main` with the user's OK.
