# Proposal

## Why

Dolby Vision profile 5 has no HDR10 or SDR base picture, so Fernsy's player shows it green and
pink and Jellyfin has to transcode it to SDR. That costs server load, loses HDR and only works
when the server can tone-map DV (it could not until a server setting was changed). Profile 8
plays as plain HDR10 today, without the Dolby Vision metadata. A spike showed that a
VideoToolbox session created as Dolby Vision HEVC (`dvh1`, with the stream's `hvcC` and `dvcC`)
gives correct DV pictures in the player's existing display layer, through Apple's licensed
pipeline. The user's Jellyfin library has 56 profile 5 and 506 profile 8 titles.

## What Changes

- The player plays Dolby Vision profile 5 and profile 8 streams as Dolby Vision: correct
  colours for profile 5, the DV picture instead of the HDR10 base layer for profile 8, in HDR on
  HDR displays and mapped by macOS on SDR displays.
- If this Mac cannot decode a stream as Dolby Vision, profile 8 falls back to the HDR10 base
  layer as today and profile 5 to the Jellyfin transcode.
- Jellyfin profile 5 items play directly instead of being transcoded.
- The info overlay names the Dolby Vision profile (e.g. "Dolby Vision 5").
- Applies to MKV and MP4 files from any source (Jellyfin, IPTV films and series) whose video
  stream carries a Dolby Vision configuration.
- Reopens the recorded non-goal "no DV processing" of `add-jellyfin-playback`: Fernsy still does
  no DV processing itself; macOS does it.

Out of scope:
- Profile 7 (dual layer): plays as HDR10 base layer as today; the enhancement layer is ignored.
- MPEG-TS streams (live TV, timeshift, recordings): unchanged; DV over IPTV live is rare and its
  in-band parameter sets would need conversion first.
- Profile 4, 8.4 (HLG) streams beyond what the same path handles without extra work; AV1 Dolby
  Vision (profile 10).
- Own tone-mapping or RPU processing (shader, libplacebo).
- Using the Dolby Vision logo.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: new requirement for Dolby Vision streams; the info overlay names the DV profile.
- `jellyfin-playback`: "Transcode fallback" no longer lists Dolby Vision profile 5 as a known
  case, except when this Mac cannot decode it as Dolby Vision.

## Impact

- `Fernsy/Player/PlaybackSession.swift` (video thread: second decode path through a
  VideoToolbox session for DV streams, seeking/flush, stats), `FFShim.c/h` (DV config record,
  HEVC parameter sets), `Fernsy/Jellyfin/JellyfinPlayback.swift` (transcode rule),
  `README.md`, `Localizable.xcstrings`.
- No new dependencies; FFmpeg stays LGPL with the same configuration.
