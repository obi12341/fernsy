# Tasks

## 1. Setup

- [x] 1.1 Get the Jellyfin server URL and a test user/API key from the user, store them in the scratchpad (mode 600) and verify `/System/Info` answers with the server version
- [x] 1.2 Build a scratchpad probe tool against Vendor/ffmpeg (custom HTTP/file I/O: streams, codec parameters, decode first 20 s, report errors) and verify it decodes a known H.264 MKV

## 2. Library census

- [x] 2.1 Read all video and music items with `MediaStreams` via the API and tabulate containers, video codecs/profiles/bit depth/HDR/DV profile, audio codecs/channels, subtitle formats with counts; verify the totals match the library item count

## 3. Format tests

- [x] 3.1 Containers (MKV, MP4, AVI, TS, WebM) via the direct stream URL with range requests: probe + Fernsy debug playback with seeking; record result per container
- [x] 3.2 Video: H.264 (incl. Hi10P), HEVC 8/10-bit, HDR10, HLG, Dolby Vision P5/P7/P8, AV1, VP9, MPEG-2, VC-1, MPEG-4/Xvid; record decoder (hardware/software), pixel format, colours (screenshot) and frame rate; note the Mac model
- [x] 3.3 Audio: AAC, AC-3, E-AC-3 (+Atmos), TrueHD (+Atmos), DTS, DTS-HD MA, FLAC, Opus, PCM, 7.1 layouts; record output channels and A/V sync after seeking
- [x] 3.4 Subtitles: SRT, ASS/SSA (styled), PGS, VobSub, DVB, embedded vs external; record what is rendered
- [x] 3.5 Music: FLAC, ALAC, MP3, AAC, hi-res (24/96, 24/192); record playback and gaps between tracks (gaps between tracks: not tested – Fernsy has no track queue yet; see report)

## 4. Jellyfin capabilities

- [x] 4.1 Query `PlaybackInfo` with a Fernsy-like device profile for representative items and record the server's decision (Direct Play / Direct Stream / Transcode) and reasons
- [x] 4.2 Run one transcoding and one subtitle burn-in request on the server; record output format, start time and server load; verify Fernsy can play the HLS output
- [x] 4.3 Document authentication, range-request support and progress reporting endpoints needed later

## 5. Report

- [x] 5.1 Write `docs/analysis/jellyfin-playback.md` (summary + recommendation, matrix, per-gap options with effort/licence/App Store notes, method, raw results) and verify every matrix cell references a test from groups 3–4
- [x] 5.2 Remove credentials and test downloads from the scratchpad and verify the report contains no host names or keys

## Workflow follow-up

- Review the report with the user; then propose the Jellyfin account change based on it.
- Archive this change once the report is accepted.
