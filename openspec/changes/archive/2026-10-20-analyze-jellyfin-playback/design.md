# Design

How the analysis is done. See proposal.md for why.

## Context

Observed in the current build (`build/ffmpeg/ffmpeg-9.0.2/config_components.h`, FFmpeg
9.0.2, LGPL, no external libraries):
- Demuxers enabled: Matroska, MOV/MP4, AVI, MPEG-TS (and FFmpeg's default set).
- Decoders enabled: H.264, HEVC, AV1 (FFmpeg native – hardware only), VP9, MPEG-2, VC-1,
  MPEG-4, AC-3, E-AC-3, TrueHD, DTS (dca), FLAC, Opus, ALAC, MP3, PGS, DVD (VobSub), ASS,
  SubRip; VideoToolbox hwaccels for HEVC, AV1, VP9. `libdav1d` is not built.
- Player (`PlaybackSession`): reads over `HTTPByteSource` with range requests (seekable
  VOD), selects audio/subtitle tracks, renders only *text* subtitles (ASS markup stripped);
  audio is resampled to stereo or 5.1 float; colour/HDR attachments are set on pixel buffers.

Working hypotheses to confirm or refute (not results):
1. Containers and most codecs play directly from Jellyfin's static stream endpoint.
2. AV1 needs hardware decoding (M3 and later); M1/M2 would need `libdav1d` (BSD-2) or
   server transcoding.
3. Bitmap subtitles (PGS, VobSub) are decoded but not rendered → player work or burn-in.
4. Dolby Vision profile 5 (no HDR10 base layer) shows wrong colours without DV processing;
   profiles 7/8 fall back to HDR10/SDR.
5. TrueHD/Atmos and DTS-HD MA decode to PCM (core + lossless), object audio is lost;
   7.1 is down-mixed to 5.1 by our resampler.
6. Styled ASS (anime) loses styling; full fidelity would need libass (ISC) + rendering.
7. Lossless music (FLAC/ALAC, hi-res) plays, but gapless playback and a music UI are new work.

## Goals / Non-Goals

**Goals:** evidence per format (test result, not assumption); clear direct-play vs transcode
boundary; costs and licensing per gap; a recommendation.

**Non-Goals:** any production code; performance tuning; a Jellyfin UI design.

## Decisions

### Test with Fernsy's real player, not only ffprobe
A probe proves demuxing; only the app proves decoding, rendering, HDR, sync and seeking.
Each format is checked in two steps: a scratchpad probe tool linked against Vendor/ffmpeg
(streams, codec parameters, decode of the first N seconds), then playback in a debug build
of Fernsy via the item's direct stream URL
(`/Videos/{id}/stream?static=true&api_key=…` with range requests), using the existing
info overlay for decoder, pixel format, dynamic range and audio.
- Rejected: judging from codec lists alone – VideoToolbox, HDR metadata and our renderer
  decide the outcome as much as the decoder.

### Two sources of media
- The user's Jellyfin server: real library, read via the API (`/Items` with
  `MediaStreams`) to build a format census (which codecs actually occur, how often), plus
  playback of representative items. Read-only; no library changes, no transcode settings
  changed on the server.
- Free test files for formats the library does not contain (e.g. Jellyfin's/Kodi's public
  sample sets, Blender open movies in AV1/HEVC/VP9, generated subtitle samples).

### Jellyfin side from the API, verified on the server
Document Direct Play / Direct Stream / Transcode via `PlaybackInfo` with a device profile,
how the server decides (codec/container/bit-rate/subtitle rules), HLS transcoding output
(fMP4/TS segments, codecs), subtitle delivery (external extraction vs burn-in),
authentication (API key vs user token) and range-request support – each tried once against
the user's server.

### Credentials
The server URL and credentials are given at implementation time and kept only in the
scratchpad (mode 600), never in the repository, the report or logs; the report names the
Jellyfin version, not the host.

### Report format
`docs/analysis/jellyfin-playback.md`: summary and recommendation first, then the matrix
(✅ direct, ⚠️ direct with gaps, ❌ needs server help), then per-gap options with effort
(S/M/L), licence and App Store notes, then method and raw results.

## Risks / Trade-offs

- [The library lacks some formats] → filled with test files; the census shows what matters.
- [Hardware differences (AV1 on M1/M2 vs M3+)] → results state the Mac model; the
  recommendation covers both.
- [Codec patent/licence questions (HEVC, Dolby, DTS) for App Store distribution] → noted as
  open legal questions in the report, not answered by us.
- [Testing streams from the user's server competes with their own use] → tests run one at
  a time; no transcodes are triggered except in the dedicated transcoding check.
