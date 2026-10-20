# Jellyfin playback analysis

Change: `openspec/changes/analyze-jellyfin-playback`. Tested 2026-10-20 against the user's
Jellyfin 12.2.0 server, on an Apple M4 Max (Mac16,9) with macOS 27.0.1, using a debug build
of Fernsy (FFmpeg 9.0.2, LGPL, no external libraries) and a probe tool linked against
`Vendor/ffmpeg`.

## Summary

Fernsy's existing player can play the user's Jellyfin library almost entirely by Direct
Play from the static stream endpoint (`/Videos/{id}/stream?static=true` with range
requests). Every container, video codec and audio codec found in the library decoded and
played, including seeking 10 minutes into the file: HEVC 10-bit HDR10/HDR10+, Dolby Vision
profiles 7 and 8 (shown as their HDR10 base layer), VP9, H.264, TrueHD, DTS-HD MA, DTS:X,
E-AC-3, PCM, FLAC and MP3. Video decoding ran on VideoToolbox, with 0 dropped frames and
about 0.5 s to the first frame.

The gaps are in rendering and presentation, not decoding:

| Gap | Share of the library | Severity |
|---|---|---|
| Bitmap subtitles (PGS, VobSub, DVB) are not offered at all | 33.9 % of videos have at least one bitmap track; 15.8 % have *only* bitmap tracks | high |
| Dolby Vision profile 5 shows wrong colours (green/purple) | 3.1 % of videos | high for these items |
| 7.1 is downmixed to 5.1; Atmos/DTS:X objects are dropped (bed/core only) | 11.8 % of videos have a 7.1 track | low |
| Styled ASS loses styling and position, and only one cue shows at a time | 2.5 % of videos have ASS | medium |
| AV1 has no software decoder (needs M3 or later) | 0 % (no AV1 in the library) | none today |
| Music: plays (FLAC up to 24/192, ALAC, MP3, AAC, Opus, Vorbis, WAV); no queue or gapless playback | 1613 tracks | new feature work |

Jellyfin can cover the remaining cases (burn-in, tone-mapping transcode). The server
transcodes fast (Intel QSV: 4K HEVC DV→H.264 SDR at about 99 fps, first segment after
1.9 s; PGS burn-in first segment after 3.7 s). Fernsy cannot play Jellyfin's **HLS**
output, though: the HLS demuxer opens the playlist, but every segment fails because Fernsy
reads through its own byte source and FFmpeg's HTTP protocol is not built. Jellyfin also
offers progressive transcoding (`stream.mkv`/`stream.ts`) when the device profile asks for
`Protocol: http`. Fernsy's player should be able to read that, but it was not tested.

### Recommendation

1. **Direct Play by default.** Build the Jellyfin client on the static stream URL and the
   existing `PlaybackSession`. Don't send a DeviceProfile for normal playback. Read
   `MediaSources`/`MediaStreams` from the item, let Fernsy pick audio and subtitle tracks,
   and report progress through `/Sessions/Playing*`.
2. **Close the player gaps by library impact:** bitmap subtitle rendering (M, no new
   licence, since FFmpeg already decodes PGS/VobSub/DVB to bitmaps), showing several text
   cues at once (S), and 7.1 output (S).
3. **Server fallback only where the player can't do it:** Dolby Vision profile 5 now, and
   AV1 on M1/M2 if such content shows up. Use a *progressive* transcode (`TranscodingProfile`
   with `Protocol: http`, container mkv or ts), not HLS. Seeking then means restarting the
   transcode with `StartTimeTicks`. Request the transcode with a DeviceProfile whose
   `CodecProfile` excludes `VideoRangeType=DOVI`. That case was tested: Jellyfin then
   tone-maps to SDR H.264.
4. **Later or optional:** libass for styled ASS (M–L), dav1d for AV1 on M1/M2 (S–M),
   real Dolby Vision processing (L, open licensing question), HLS support (M, only if
   fallbacks turn out to need seeking without a restart).
5. **Pitfall to design for:** if the client does not send `SubtitleStreamIndex`, Jellyfin
   picks the default subtitle track itself. If that track is PGS, the whole item is
   transcoded for burn-in (seen in J2). Always send `SubtitleStreamIndex=-1` or the track
   the user chose.

## Format matrix

✅ plays directly · ⚠️ plays directly with a gap · ❌ needs server help (transcode/burn-in) or
new player work. Test ids are explained under [Method](#method). Raw results are in
[Condensed raw results](#condensed-raw-results).

### Containers

| Container | Result | Notes | Tests |
|---|---|---|---|
| Matroska (mkv) | ✅ | Range requests, seek to 600 s, 0 drops | L-* (all library video tests) |
| MP4 (H.264/HEVC `hvc1`, AV1) | ✅ | | L-mp4, T-mp4_hevc_movtext, T-mp4_av1_aac |
| WebM (VP9/AV1 + Opus) | ✅ | | T-webm_vp9_opus, T-webm_av1_opus |
| AVI (Xvid + MP3) | ✅ | | T-avi_xvid_mp3 |
| MPEG-TS / M2TS | ✅ | MPEG-2 and VC-1 interlaced, deinterlaced with bwdif | T-ts_mpeg2i_ac3, T-ext_vc1_m2ts, T-ext_dvbsub_ts |
| ASF/WMV (VC-1) | ✅ | Not in the library | T-ext_vc1_wmv |
| HLS (Jellyfin transcode output) | ❌ | Segments fail to open, "Could not open the stream" | J5 |

### Video

| Format | Result | Decoder / pixel format / range shown | Tests |
|---|---|---|---|
| H.264 8-bit (High/Main) | ✅ | VideoToolbox, NV12, SDR | L-h264_sdr_srt, L-aac, L-pgs, L-mp4 |
| H.264 Hi10P | ✅ | VideoToolbox, P010 (hardware on M4 Max) | T-mkv_h264_hi10p_flac71 |
| H.264 interlaced (PAFF/MBAFF) | ⚠️ | VideoToolbox refuses it and decoding falls back to software, which still runs at full frame rate. No deinterlacer was engaged; the sample looked progressive (no combing) | L-interlaced |
| HEVC 8-bit SDR 4K | ✅ | VideoToolbox, NV12 | L-hevc8_sdr |
| HEVC 10-bit HDR10 | ✅ | VideoToolbox, P010, HDR10 (PQ); colours correct in screenshots | L-hevc10_hdr10, L-truehd_atmos, L-dtsx, L-pcm |
| HEVC HDR10+ | ⚠️ | Plays as static HDR10. The dynamic metadata (SEI present in 100 % of frames) is not applied | L-hevc_hdr10plus |
| HEVC HLG | ✅ | P010, HLG | T-mkv_hevc_hlg_eac3 |
| Dolby Vision P8.1 (HDR10 base) | ⚠️ | Plays the HDR10 base layer; colours correct; the RPU is ignored. The overlay says "Dolby Vision", which overstates what is rendered | L-dv_p8, L-dv_p8_hdr10plus, L-eac3_atmos |
| Dolby Vision P7 (BL+EL) | ⚠️ | HDR10 base layer only; enhancement layer and RPU ignored; colours correct | L-dv_p7_el |
| Dolby Vision P5 (IPTPQc2, no fallback) | ❌ | Decodes, but colours are wrong (strong green/purple cast) | L-dv_p5 (screenshot), J1, J4 |
| AV1 8/10-bit, HDR10 4K | ✅ on M3+ / ❌ on M1/M2 | VideoToolbox, P010, HDR10 on M4 Max. Software decode fails (0 frames, 61 errors) because the native FFmpeg AV1 decoder needs a hwaccel and dav1d is not built. Not tested on an M1/M2 Mac | T-mkv_av1_hdr10_4k_opus71, T-webm_av1_opus, T-mp4_av1_aac |
| VP9 Profile 0 / Profile 2 10-bit 4K | ✅ | VideoToolbox, NV12/P010 | L-vp9, T-webm_vp9_opus |
| MPEG-2 (DVD, interlaced TS) | ✅ | Software, bwdif deinterlacing for interlaced input | T-mkv_mpeg2_dvd, T-ts_mpeg2i_ac3 |
| VC-1 (progressive WMV, interlaced M2TS) | ✅ | Software, bwdif | T-ext_vc1_wmv, T-ext_vc1_m2ts |
| MPEG-4 Part 2 / Xvid | ✅ | Software | T-avi_xvid_mp3 |

### Audio

Fernsy outputs at most 6 channels (`ffs_output_channels`: ≥6 → 6, otherwise 2).

| Format | Result | Output | Tests |
|---|---|---|---|
| AAC LC stereo / 5.1 | ✅ | 2 / 6 ch | L-aac, L-mp4, T-mp4_hevc_movtext |
| AC-3 2.0 / 5.1 | ✅ | 2 / 6 ch | L-hevc8_sdr, L-pgs |
| E-AC-3 5.1 | ✅ | 6 ch | L-hevc10_hdr10, L-dv_p8 |
| E-AC-3 + Atmos (JOC) | ⚠️ | 5.1 bed only, objects lost | L-eac3_atmos |
| E-AC-3 7.1 | ⚠️ | Downmixed to 5.1 | L-eac3_71 |
| TrueHD 7.1 (+Atmos) | ⚠️ | Decodes 7.1 lossless, downmixed to 5.1, objects lost | L-truehd_atmos, L-eac3_71 |
| DTS core 5.1 | ✅ | 6 ch | L-dts_core, L-h264_sdr_srt |
| DTS-ES 6.1 | ⚠️ | Downmixed to 5.1 | L-dts_es_61 |
| DTS-HD MA / HRA 7.1 | ⚠️ | Lossless decode (s32p), downmixed to 5.1 | L-dtshd_ma |
| DTS-HD MA + DTS:X | ⚠️ | 7.1 core+lossless, downmixed to 5.1, objects lost | L-dtsx |
| PCM s24le 2.0 / 7.1 | ✅ / ⚠️ | 7.1 downmixed to 5.1 | L-pcm, T-mkv_pcm_s24le_71 |
| FLAC 7.1 | ⚠️ | Downmixed to 5.1 | T-mkv_h264_hi10p_flac71 |
| Opus 5.1 / 7.1 | ✅ / ⚠️ | 7.1 downmixed to 5.1 | T-webm_vp9_opus, T-mkv_av1_hdr10_4k_opus71 |
| MP3, MP2 | ✅ | | T-avi_xvid_mp3, T-ext_dvbsub_ts |

Track switching between 7.1 TrueHD/DTS-HD MA/E-AC-3 tracks through the audio menu worked
(L-dtshd_ma, L-eac3_71). A/V sync after seeking was not measured objectively. After every
seek to 600 s the audio clock lead stayed constant (about 1.0 s of buffer) with 0 dropped
frames and 0 rebuffers.

### Subtitles

| Format | Result | What is rendered | Tests |
|---|---|---|---|
| SRT (embedded) | ✅ | Text with italics; the track is listed and selectable | T-sub_srt, L-hevc10_hdr10 (listed) |
| mov_text (MP4) | ✅ | Text | T-sub_movtext |
| ASS/SSA (styled) | ⚠️ | Plain white text at the bottom. Fonts, colours, positions, `\move`, rotation and karaoke are lost, and with several cues active at the same time only the newest one is shown | T-sub_ass (screenshots), L-ass |
| PGS (embedded) | ❌ | Not listed; Fernsy only offers text subtitle tracks (`ffs_is_text_subtitle`). The FFmpeg decoder produces bitmaps (probe: bitmap rects > 0) | L-pgs, L-truehd_atmos, L-interlaced, J1, J4 |
| VobSub / DVDSUB (embedded) | ❌ | Not listed; decoder produces bitmaps | L-dvdsub, L-dts_core, J1 |
| DVB subtitles (TS) | ❌ | Not listed; decoder produces bitmaps | T-ext_dvbsub_ts (screenshot) |
| External sidecar text (srt/ass next to the file) | ⚠️ | Not part of the static stream. It has to be fetched from the subtitle endpoint and fed to the player as a second input | J3 (no external text sidecars exist in the library) |
| External sidecar bitmap (PGS/VobSub) | ❌ | The server can't deliver them as a file in the tested formats (HTTP 400); burn-in only | L-dvdsub_ext, L-pgs_ext, J3 |

### HDR and Dolby Vision summary

| Case | Result | Tests |
|---|---|---|
| HDR10 (PQ) | ✅ | L-hevc10_hdr10 |
| HDR10+ | ⚠️ static HDR10 | L-hevc_hdr10plus |
| HLG | ✅ | T-mkv_hevc_hlg_eac3 |
| DV P8.1 / P7 | ⚠️ HDR10 base layer | L-dv_p8, L-dv_p8_hdr10plus, L-dv_p7_el |
| DV P5 | ❌ wrong colours; server tone-mapping works | L-dv_p5, J4 |

### Music

| Format | Result | Tests |
|---|---|---|
| FLAC 16/44.1, 24/48, 24/96, 24/192 | ✅ native sample rate shown (44/48/96/192 kHz), seek to 60 s | L-flac16_44, L-flac24_48, L-flac24_96, L-flac24_192 |
| MP3 | ✅ | L-mp3 |
| ALAC 24/96 (m4a) | ✅ | T-music_alac_24_96 |
| AAC (m4a), Opus (ogg), Vorbis (ogg), WAV 24/192 | ✅ | T-music_aac, T-music_opus, T-music_vorbis, T-music_wav_24_192 |
| Gapless playback between tracks | not tested | Fernsy has no track queue; there is nothing to test until a music player exists |

## Library census

The user's library: 1806 video items (movies and episodes) and 1613 music tracks. All
items were read through `/Items` with `MediaStreams`, and the totals match the library item
counts. Shares are per video item unless stated otherwise.

| Aspect | Values |
|---|---|
| Container | MKV 99.9 % (1805), MP4 0.1 % (1) |
| Video codec | HEVC 64.6 % (1166: Main 10 1026, Main 140), H.264 35.4 % (639), VP9 0.1 % (1), AV1/MPEG-2/VC-1/MPEG-4 0 % |
| Resolution | 2160p 64.6 %, 1080p 25.2 %, 720p 10.1 %, SD 0.2 % |
| Dynamic range | SDR 48.4 % (875), HDR10 12.3 % (223), HDR10+ 5.0 % (90), Dolby Vision 34.2 % (618) |
| Dolby Vision profiles | P8.1 28.0 % (506), P7 with EL 3.1 % (56), **P5 3.1 % (56)** |
| Interlaced | 0.1 % (1) |
| First audio track | E-AC-3 56.6 % (1022, of which Atmos 190), AC-3 26.9 % (485), DTS family 12.3 % (222: DTS-HD MA 115, DTS 101, HRA 4, ES 2), AAC 2.7 % (49), TrueHD 1.6 % (28) |
| Any audio track (3851 tracks) | E-AC-3 2100 (Atmos 671), AC-3 1024, DTS-HD MA 241 (DTS:X 9), TrueHD 237 (Atmos 220), DTS 132, AAC 93, DTS-HD HRA 9, DTS-ES 4, PCM 2 |
| Max channels per item | 2.0: 16.2 %, 5.1: 71.7 %, 6.1: 0.2 %, **7.1: 11.8 %** |
| Subtitle tracks | SRT 13745, PGS 1607 (+2 external), VobSub 669 (+17 external), ASS 116 |
| Items with any bitmap subtitle | **33.9 %** (613) |
| Items with only bitmap subtitles | **15.8 %** (286) |
| Items with ASS | 2.5 % (45) |
| Items without subtitles | 9.1 % (165) |
| Music | FLAC 89.5 % (1444), MP3 10.5 % (169); 24-bit 9.0 % (145); above 48 kHz 3.1 % (50: 34× 96 kHz, 16× 192 kHz); all stereo |

## Gaps and options

Effort: S = days, M = 1–3 weeks, L = more than 3 weeks or uncertain.

### 1. Bitmap subtitles (PGS, VobSub, DVB): 33.9 % of items

- **Render in the player (recommended).** FFmpeg already decodes these to palettised
  `AVSubtitleRect` bitmaps with position and timing. Convert them to RGBA and draw them as
  an overlay scaled from the subtitle canvas (PGS: video size, VobSub: 720×576/480) to the
  video rect, then list the tracks in the menu. Effort **M**. Licence: none beyond the
  existing LGPL FFmpeg. App Store: no concerns. This also covers DVB subtitles for IPTV.
- **Jellyfin burn-in.** Works (J5: QSV, first segment 3.7 s). It needs a transcode
  playback path in Fernsy (progressive S, HLS M), loads the server and re-encodes the whole
  video for a subtitle. Keep it as a fallback, not the plan.
- External bitmap sidecars (19 tracks) can only be burned in by the server. Rare; accept
  this.

### 2. Dolby Vision profile 5: 3.1 % of items

- **Server tone-mapping (recommended for now).** A DeviceProfile with a `CodecProfile`
  `VideoRangeType EqualsAny …` without `DOVI` yields `TranscodeReasons=VideoRangeTypeNotSupported`.
  The server then sends H.264 SDR, tone-mapped by its VPP; colours looked plausible (J4).
  Fernsy needs a transcode playback path for this: progressive mkv/ts is effort **S**,
  untested, and seeking needs a transcode restart; HLS is **M**. Server load: 4K at about
  99 fps on QSV.
- **DV reshaping in Fernsy.** Either let macOS do it, by handing VideoToolbox/
  AVSampleBufferDisplayLayer `dvh1` sample buffers with a `dvcC` configuration (unverified
  whether the system applies DV processing outside AVPlayer), or apply the RPU in a Metal
  shader. libplacebo (LGPL-2.1) and libdovi (MIT) implement the maths, but libplacebo needs
  Vulkan/MoltenVK. Effort **L**. Licence: open question for Dolby (see below).
- Detect P5 from `DvProfile`/`VideoRangeType=DOVI` and route only those items to the
  fallback. P7/P8 stay on Direct Play, because their HDR10 base layer looks correct.

### 3. Multichannel and object audio: 11.8 % of items have 7.1

- **7.1 output.** Allow 8 output channels when the device supports them
  (`AVSampleBufferAudioRenderer` accepts 7.1 layouts; downmix to 5.1/2.0 otherwise).
  Effort **S**, no licence impact.
- **Atmos / DTS:X objects.** Not possible with LGPL FFmpeg decoding. Passing E-AC-3 JOC
  compressed to AVFoundation might give Spatial Audio, but this is unverified. TrueHD
  Atmos and DTS:X have no system decoder. Effort **L**, uncertain; not recommended now.
- Server transcoding doesn't help here: it would cost quality, not add objects.

### 4. Styled ASS: 2.5 % of items

- **Several cues at once (do first).** The player shows only the newest cue. That is a
  bug for overlapping SRT cues as well. Effort **S**.
- **libass** (ISC) with FreeType (FTL), FriBidi (LGPL-2.1) and HarfBuzz (MIT), using
  CoreText for fonts and the fonts embedded in MKV attachments. Effort **M–L** (build
  integration like FFmpeg, bitmap overlay shared with gap 1). App Store: fine with
  dynamic linking, under the same LGPL obligations as FFmpeg.
- **Jellyfin burn-in** for ASS is supported by the server (fallback).

### 5. AV1 without hardware decoding (M1/M2): 0 % of the library today

- **dav1d** (BSD-2) through FFmpeg's `libdav1d` wrapper. Effort **S–M**. Licence fine,
  App Store fine. A 4K 10-bit software decode may be heavy on M1.
- **Jellyfin transcode** as the fallback (needs a transcode path, see gap 2).
- Not urgent, because the library contains no AV1. Results above are from an M4 Max only.

### 6. HDR10+ dynamic metadata: 5.0 % of items

Plays as HDR10, which looks correct. Applying the dynamic metadata (attaching
`kCVImageBufferHDR10PlusMetadata`-style per-frame data, if supported) would be effort
**M** and probably unnoticeable on most displays. Not recommended now.

### 7. Music

All formats in the library play. A music UI, queue, gapless transitions (pre-roll the next
item into the same audio renderer) and a Now Playing integration are new feature work
(**M–L**) for a separate change.

### 8. Transcode playback path (needed by gaps 2 and 5 if server help is used)

- **Progressive** (`TranscodingProfile Protocol: http`, container mkv or ts). PlaybackInfo
  returned `stream.mkv` (J6). Effort **S**: a non-seekable source, and seeking restarts
  with `StartTimeTicks`. Not tested in Fernsy.
- **HLS.** Route the FFmpeg HLS demuxer's segment opens (`io_open`) through
  `HTTPByteSource`, or parse the playlist in Swift. Effort **M**.

## Jellyfin capabilities

| Topic | Finding | Test |
|---|---|---|
| Direct Play | `/Videos/{id}/stream?static=true` (`/Audio/{id}/stream?static=true` for music) serves the original file with `Accept-Ranges: bytes` and `206` + `Content-Range` for every range | L-* (`status 206` lines), J3 |
| Decision | `POST /Items/{id}/PlaybackInfo` with a DeviceProfile returns `SupportsDirectPlay/DirectStream/Transcoding`, per-subtitle `DeliveryMethod` (Embed/External/Encode) and a `TranscodingUrl` whose query carries `TranscodeReasons` | J1, J2 |
| Subtitle delivery | Text subtitles: `Embed` (in the stream) or `External` via `/Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.{srt,ass,vtt}`. The first extraction of an embedded SRT took 38 s (reads the file); ASS→ass 7 s; vtt from cache 0 s. Bitmap subtitles: `Encode` (burn-in) only; PGS→srt and external VobSub `.sub` return 400 | J3 |
| Transcoding | HLS by default (`master.m3u8`, VOD playlist, MPEG-TS segments, 3 s target duration), or progressive when the profile says `Protocol: http`. Server: Intel QSV, VPP tone-mapping on, HEVC encoding allowed, AV1 encoding off | J4, J5, J6 |
| Stopping a transcode | `DELETE /Videos/ActiveEncodings?deviceId=…&playSessionId=…` → 204 | J4, J5 |
| Authentication | `POST /Users/AuthenticateByName` with `Authorization: MediaBrowser Client="…", Device="…", DeviceId="…", Version="…"` returns `AccessToken` and the user id. Later requests may send the token as `Authorization: MediaBrowser …, Token="…"`, `X-Emby-Token`, or as the `api_key`/`ApiKey` query parameter (all accepted on 12.2.0). Quick Connect (`/QuickConnect/Initiate`) exists as a passwordless login | J3 |
| Unauthenticated streams | The static stream endpoint answered a range request **without any token** (206). Fernsy must send the token anyway; this is a server-side observation for the user, not something to rely on | J3 |
| Progress reporting | `POST /Sessions/Playing` (start), `/Sessions/Playing/Progress` (every ~10 s and on pause/seek: `ItemId`, `MediaSourceId`, `PositionTicks` = seconds × 10⁷, `IsPaused`, `PlayMethod`, `PlaySessionId`, `AudioStreamIndex`, `SubtitleStreamIndex`), `/Sessions/Playing/Stopped`, `/Sessions/Playing/Ping` for transcodes. Played state: `/UserPlayedItems/{id}`; resume position comes back in `UserData.PlaybackPositionTicks`. Endpoints confirmed in the server's OpenAPI document; not called, to keep the library unchanged | J3 |
| Default subtitle trap | Without `SubtitleStreamIndex`, the server picks the default track (user setting `SubtitleMode=Default`). One HDR10 item then went to burn-in because that track is PGS | J2 |
| DV P5 in a naive profile | Without a `VideoRangeType` condition the server reports Direct Play for DV P5, so the client must exclude `DOVI` itself to get tone-mapping | J1, J4 |

## Method

- **Probe** (`jfprobe`, scratchpad): a C tool linked against `Vendor/ffmpeg`. For each test
  it range-downloads about 25 s of the item, prints streams and codec parameters, and
  decodes the first 20 s of every stream, preferring VideoToolbox as Fernsy does. It
  reports hardware or software decoding, the output pixel format, HDR10+/DV RPU/mastering
  metadata counts, audio channel layouts and Fernsy's output channel count, and the
  subtitle decoder output (text/ASS/bitmap). A `-sw` mode forces software video decoding
  (used for AV1).
- **App:** the debug build with the `IPTV_PLAYURL` hook (`AppModel.swift`, `#if DEBUG`)
  plays any URL through the VOD path. A local proxy added the auth header so no token
  appeared in URLs or logs. Library items were seeked to 600 s (music 60 s, test files
  15 s) with `IPTV_TESTSEEK`. The info overlay was logged (`[player] stats`: codec,
  decoder, pixel format, dynamic range, audio, drops, rebuffers) and screenshots were
  taken after about 10 s and at the end. Tracks were switched through the menus
  (accessibility).
- **Test ids:**
  - `L-<label>`: one representative item from the user's library per format case, picked
    from the census (`picks`).
  - `T-<name>`: test media for formats the library lacks. Generated with FFmpeg (testsrc2,
    SMPTE bars, tones per channel, a styled ASS and an SRT file) plus three public samples
    from samples.ffmpeg.org (VC-1 WMV, VC-1 interlaced M2TS, DVB subtitles in TS). Served
    locally with range support.
  - `J<n>`: Jellyfin API checks (below).
- **Machine:** Apple M4 Max (Mac16,9), macOS 27.0.1. AV1 hardware decoding exists on M3 and
  later, so the M1/M2 statement comes from the software-only probe, not from a test on
  such a Mac.
- **Server:** the user's Jellyfin 12.2.0 server. Read-only, except for the two transcodes
  in J4/J5, which were stopped right after measuring. Streams ran one at a time.

## Condensed raw results

### Library items (probe + Fernsy)

Probe: all `RESULT OK`, 0 decode errors. Fernsy: 0 dropped frames and 0 rebuffers after the
seek in every run. Abbreviations: VT = VideoToolbox (hardware), SW = software.

| Test | Source | Probe video | Probe audio → Fernsy out | Fernsy overlay after seek |
|---|---|---|---|---|
| L-h264_sdr_srt | mkv, H.264 1080p, DTS 5.1, SRT + ext. VobSub | VT nv12 | dts 6ch → 6 | H.264 VT NV12 SDR, DTS 5.1, 25 fps |
| L-hevc8_sdr | mkv, HEVC Main 4K | VT nv12 | ac3 2/6ch | HEVC VT NV12 SDR, AC-3 5.1 |
| L-hevc10_hdr10 | mkv, HEVC Main10 HDR10 | VT p010, mdcv 460/460 | eac3 6ch | HEVC VT P010 HDR10 (PQ), 23.95 fps |
| L-hevc_hdr10plus | HDR10+ | VT p010, hdr10+ 463/463 | eac3 6ch | HDR10 (PQ) |
| L-dv_p5 | DV P5 | VT p010, dovi_rpu 458/458, no mdcv | eac3 6ch | "Dolby Vision", **green/purple cast** in screenshot |
| L-dv_p7_el | DV P7 FEL, 62 Mbit/s | VT p010, rpu + mdcv | ac3, DTS-HD MA 6ch | "Dolby Vision", colours correct (HDR10 base) |
| L-dv_p8 | DV P8.1 | VT p010, rpu + mdcv | eac3 6ch | "Dolby Vision", colours correct |
| L-dv_p8_hdr10plus | DV P8.1 + HDR10+ | VT p010, hdr10+ + rpu + mdcv | eac3 6ch | colours correct; 41 SRT tracks parsed |
| L-vp9 | VP9 Profile 2 10-bit 4K | VT p010 | eac3/aac (31 tracks) | VP9 VT P010 SDR, 24 fps |
| L-mp4 | mp4, H.264, AAC 5.1 | VT nv12 | aac 6ch | H.264 VT, AAC 5.1 |
| L-interlaced | H.264 1080i, 50 Mbit/s | **SW** yuv420p (VT init fails) | DTS-HD MA/DTS | H.264 SW NV12, 25 fps, no deinterlacer, no combing visible |
| L-truehd_atmos | HEVC HDR10, TrueHD Atmos 7.1 | VT p010 | truehd 8ch s32 → **6** | TrueHD 7.1 selected, HDR10 |
| L-eac3_71 | E-AC-3 7.1 + TrueHD 7.1 | VT p010 | eac3 8ch → 6, truehd 8ch → 6 | switch to E-AC-3 7.1 via menu OK |
| L-eac3_atmos | E-AC-3 JOC 5.1 | VT p010 | eac3 6ch | E-AC-3 5.1 |
| L-dtshd_ma | DTS-HD MA 7.1 + HRA 7.1 | VT nv12 | dts 8ch s32p → 6 | switch to DTS-HD MA 7.1 via menu OK |
| L-dtsx | DTS-HD MA + DTS:X 7.1 | VT p010 | dts 8ch → 6 | DTS 7.1, HDR10 |
| L-dts_core | DTS 5.1 + PGS + VobSub | VT nv12 | dts 6ch | PGS/VobSub decode to bitmaps (probe) |
| L-dts_es_61 | DTS-ES 6.1 | VT nv12 | dts 7ch → 6 | DTS 7 channels |
| L-pcm | PCM s24le 2.0, DTS-HD MA 6.1 | VT p010 | pcm 2ch s32 | PCM_S24LE stereo, HDR10 |
| L-aac / L-ass | H.264, AAC 2.0, 3× ASS | VT nv12 | aac 2ch | ASS tracks listed |
| L-pgs / L-dvdsub | H.264, AC-3, PGS + VobSub | VT nv12 | ac3 6ch | bitmap tracks not listed |
| L-pgs_ext / L-dvdsub_ext | ext. PGS/VobSub sidecars | VT | dts | sidecars not in the stream |
| L-flac16_44 … L-flac24_192 | FLAC 16/44.1 – 24/192 | – | flac s16/s32 2ch | FLAC stereo 44/48/96/192 kHz |
| L-mp3 | MP3 | – | mp3 2ch | MP3 stereo 44 kHz |

### Test media (probe + Fernsy)

| Test | Probe | Fernsy overlay |
|---|---|---|
| T-avi_xvid_mp3 | mpeg4 SW, mp3 | MPEG-4 SW, 25 fps |
| T-ts_mpeg2i_ac3 | mpeg2 SW, ac3 6ch | MPEG-2 SW, bwdif 2×, 50 fps |
| T-mkv_mpeg2_dvd | mpeg2 SW (720×576 → 1024×576), ac3 | MPEG-2 SW, 25 fps |
| T-webm_vp9_opus | vp9 VT, opus 5.1 | VP9 VT, Opus 5.1 |
| T-webm_av1_opus / T-mp4_av1_aac | av1 VT nv12; **`-sw`: 0 frames, 61 errors** | AV1 VT NV12, 24 fps |
| T-mkv_av1_hdr10_4k_opus71 | av1 VT p010 mdcv; opus 8ch → 6; `-sw` fails | AV1 VT P010 HDR10 (PQ), Opus 7.1 |
| T-mkv_h264_hi10p_flac71 | h264 VT p010; flac 8ch → 6 | H.264 VT P010, FLAC 7.1 |
| T-mkv_hevc_hlg_eac3 | hevc VT p010 | HLG, bars correct |
| T-mp4_hevc_movtext | hevc `hvc1` VT, mov_text | text shown |
| T-mkv_pcm_s24le_71 | pcm 8ch → 6 | PCM 7.1 |
| T-mkv_styled_ass (T-sub_ass, T-sub_srt) | 6 ASS events, 2 SRT events | ASS: only "Karaoke line", white, bottom; SRT: cue shown |
| T-ext_vc1_wmv / T-ext_vc1_m2ts | vc1 SW | VC-1 SW (interlaced: bwdif 2×, 50 fps) |
| T-ext_dvbsub_ts | dvb_subtitle 12 events, 5 bitmap rects | no subtitle menu entry |
| T-music_alac_24_96, _aac, _opus, _vorbis, _wav_24_192 | all decode | ALAC 96 kHz, WAV 192 kHz, … |

### Jellyfin API checks

DeviceProfile used for J1/J2 ("Fernsy-like"): Direct Play for video containers
mkv/webm/mp4/m4v/mov/avi/ts/m2ts with h264, hevc, av1, vp9, mpeg2video, vc1, mpeg4 and
aac, ac3, eac3, truehd, dts, flac, opus, alac, mp3, mp2, vorbis, pcm; audio containers
flac/mp3/m4a/ogg/opus/wav. Subtitle profiles: srt/ass External or Embed, mov_text Embed,
no bitmap formats. Transcoding: HLS, TS, h264/hevc + aac/ac3/eac3, max 6 channels.
Max bitrate 200 Mbit/s.

| Id | Request | Server decision |
|---|---|---|
| J1 | PlaybackInfo, subtitles off (`SubtitleStreamIndex=-1`) or text subtitle | Direct Play for HDR10, HDR10+, DV P5/P7/P8, TrueHD, DTS-HD MA, DTS:X, VP9, MP4, interlaced, FLAC 24/192, MP3, ASS. Bitmap subtitles always `DeliveryMethod=Encode` |
| J1 | PlaybackInfo with a PGS/VobSub track (incl. external VobSub) | HLS transcode, `TranscodeReasons=SubtitleCodecNotSupported`. With DTS audio also `AudioCodecNotSupported`, because the TS transcode target allows only aac/ac3/eac3 |
| J2 | PlaybackInfo without `SubtitleStreamIndex` on an HDR10 item with a PGS track | the server picked the PGS track → transcode (`SubtitleCodecNotSupported`); with `-1` → Direct Play |
| J3 | Auth and range: 100-byte range on the static audio stream | 206 with `Content-Range` for no token, `api_key`, `ApiKey`, `X-Emby-Token`, `Authorization` header. Subtitle endpoint: embedded SRT→srt 200 (38 s first time), ASS→ass 200 (7 s), ASS→vtt 200, PGS→srt 400, external VobSub→sub 400 |
| J4 | Transcode: DV P5 4K with a profile excluding `DOVI` | `VideoRangeTypeNotSupported`; master.m3u8 0.03 s; `avc1.424029, ec-3`, 3840×2160, VIDEO-RANGE=SDR; segment 0 (11.9 MB) after **1.9 s**, next segments 0.6–0.7 s; QSV, **99 fps**, audio copied (E-AC-3 5.1); output H.264 bt709, decodes on VT; frame colours plausible (no cast); stopped (204) |
| J5 | Burn-in: H.264 1080p with PGS selected | `SubtitleCodecNotSupported`; `avc1.640029, ac-3`, 1080p; segment 0 after **3.7 s**, next 0.2 s; QSV; audio copied. **Fernsy debug build with the variant playlist: `hls` demuxer opens it, all 842 segments "failed too many times", player error "Could not open the stream" (AVERROR_INVALIDDATA)**; stopped (204) |
| J6 | PlaybackInfo with `Protocol: http`, container mkv (decision only, no transcode started) | `stream.mkv` progressive transcode URL, same reasons |

## Open legal questions (not answered here)

- HEVC decoding (VideoToolbox hardware decoder and FFmpeg software fallback) in an App Store
  app: does Apple's platform licence cover it, and does the FFmpeg HEVC software decoder
  need its own patent licence?
- Dolby: decoding AC-3, E-AC-3 and TrueHD with FFmpeg in a paid App Store app; any Dolby
  Vision processing (gap 2); use of the names "Dolby Vision" and "Atmos" in the UI (the
  overlay already shows "Dolby Vision").
- DTS: decoding DTS/DTS-HD with FFmpeg's `dca` decoder in an App Store app; the "DTS" name in
  the UI.
- MPEG-2, VC-1 and MPEG-4 Part 2: patent status for distribution (believed mostly expired,
  not verified).
- These questions already apply to the current IPTV app, which ships the same decoders.
