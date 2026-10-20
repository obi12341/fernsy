# Tasks

## 1. Setup

- [x] 1.1 Get Jellyfin credentials (scratchpad only, mode 600), pick test items (HEVC HDR10 + TrueHD film, DV P5 film, film with PGS, film with external SRT, a series with ≥ 3 episodes) and back up their complete user data; verify the backup file lists every test item

## 2. Direct play and transcode

- [x] 2.1 `PlayItem.Kind.jellyfin`, direct-play URL, Play buttons (film, series, episodes, home, context menus); verify the HEVC HDR10 + TrueHD film plays directly (info overlay: direct play, VideoToolbox, HDR10) with `JF_SERVER/USER/PASS`
- [x] 2.2 Transcode request (PlaybackInfo with device profile, explicit subtitle index, DOVI excluded) and playing the progressive stream (mkv, else ts); verify the DV P5 film plays transcoded with correct colours (screenshot) and the server lists one active encoding that disappears after closing — mkv plays, encoding cleaned up; colours correct (tonemap_opencl) after enabling the server's "Prefer OS native … VA-API decoders" setting; with QSV decoding they were green/pink (see design)
- [x] 2.3 Local decision rules (DV P5, undecodable codecs) and the one-time fallback after a failed direct-play open; verify the rule picks transcode for DV P5 and direct play for the others, and a direct play forced to fail (altered local URL) switches to transcode
- [x] 2.4 Seeking and track changes in a transcode via restart with offset; verify a seek to 1:10:00 shows 1:10:00 and the full duration, and only one encoding is active afterwards

## 3. Server state

- [x] 3.1 Progress reporting (start, progress, pause/seek, stopped, ping) and resume from the server position with Resume/From the beginning; verify stopping at ~55 % shows the position in the web client data (`/Items/{id}` UserData) and resuming starts there
- [x] 3.2 Refresh user data after playback so grids/Home update; verify the film's progress bar appears in Fernsy after closing the player

## 4. Tracks and subtitles

- [x] 4.1 Map Jellyfin stream indices to FFmpeg streams, external text subtitles via the subtitle endpoint (SRT → cues); verify the external SRT is listed and shown in sync — indices match 1:1 (28 Years Later); the library has no external text subtitles, so the same SRT endpoint was verified with an embedded subrip track in a transcode, in sync and kept across seek restarts
- [x] 4.2 Bitmap subtitles: shim decoding to RGBA rects, bitmap cues in the engine, overlay scaled to the video rect; verify PGS on the test film (screenshot) and DVB subtitles on an IPTV channel in a debug run that has them, or note if none is available — PGS and VobSub shown in direct play (HDR10 film, letterboxed); external VobSub burnt in by the server; no DVB source available (demo server has none, the user's IPTV account is single-stream)
- [x] 4.3 Show all active text cues at once; verify with a subtitle file containing overlapping cues

## 5. Next episode

- [x] 5.1 Next-episode lookup and end-of-episode overlay with 10 s countdown, Play Now, Cancel; verify on the test series by seeking near the end (screenshot) and that the next episode starts after the countdown

## 6. Finish

- [x] 6.1 Translations (xcstringstool sync, no untranslated keys), README note on Jellyfin playback and transcoding
- [x] 6.2 Restore the backed-up user data of all test items and verify it matches the backup; log out test sessions, remove credentials and verify no host, user or token is in the repository or logs

## Workflow follow-up

- Archive after the user's review and merge `change/add-jellyfin-playback` into `main`.
