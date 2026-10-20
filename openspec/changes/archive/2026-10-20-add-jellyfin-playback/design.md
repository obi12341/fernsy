# Design

## Context

- Player: `PlayerEngine.load(url:isLive:startAt:)` → `PlaybackSession(.network)` reads through
  `HTTPByteSource` with range requests (seekable VOD); FFmpeg seeks by timestamp. Subtitles:
  only text codecs are listed (`ffs_is_text_subtitle`), decoded to `SubtitleCue` text; the engine
  keeps cues and shows the newest active one. Resume positions are local (`resume.<key>`).
- Jellyfin: `JellyfinStore`/`JellyfinClient` (browser change) with session token, items with
  `MediaSources`/`MediaStreams` on detail load; Play buttons disabled.
- Analysis results (archived `analyze-jellyfin-playback`, report kept locally): direct play via
  `/Videos/{id}/stream?static=true` with ranges works for the whole library on an M4 Max;
  progressive transcodes (`TranscodingProfile Protocol: http`, mkv/ts) are offered but were not
  played in Fernsy; HLS output cannot be read (no FFmpeg HTTP protocol); DV P5 needs the server's
  tone-mapping; without `SubtitleStreamIndex` the server may pick a PGS track and transcode.

## Goals / Non-Goals

**Goals:** direct play by default with the existing player; a transcode only when needed; the
server's state (resume, played, Next Up) stays right; bitmap subtitles in the player.

**Non-Goals:** see proposal (7.1, libass, DV processing, HLS, dav1d).

## Decisions

### Item kind and URLs
`PlayItem.Kind.jellyfin(itemId:, mediaSourceId:)`. Direct play URL:
`/Videos/{id}/stream?static=true&mediaSourceId=…&api_key=<token>` (the token in the query
because `HTTPByteSource` sends no auth header; URLs are never logged with the token). The
player window and engine are shared with IPTV.

### Choosing direct play or transcode
Before playing, Fernsy decides from the item's `MediaStreams` (no PlaybackInfo round trip for
the normal case):
- Transcode when the video is Dolby Vision without a compatible base layer
  (`VideoRangeType == "DOVI"`, i.e. profile 5), or the codec is one the bundled FFmpeg cannot
  decode or this Mac has no hardware decoder for and FFmpeg has no software decoder (AV1 →
  `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`).
- Otherwise direct play. If the direct-play session fails while opening (`.failed` before
  `.started`), the engine retries once as a transcode.
- Rejected: always asking PlaybackInfo with a full device profile – the server's codec rules do
  not know our player (it would transcode bitmap subtitles and some audio we play fine).

### Transcode request
`POST /Items/{id}/PlaybackInfo` with `userId`, `mediaSourceId`, `startTimeTicks`,
`audioStreamIndex`, `subtitleStreamIndex` (always explicit: chosen index or -1),
`enableDirectPlay=false`, `enableDirectStream=false` and a DeviceProfile whose
`TranscodingProfiles` has one progressive (`Protocol: http`) video profile, container mkv
(fallback ts if mkv does not stream cleanly – checked in task 2.2), video h264/hevc, audio
aac/ac3/eac3, and a `CodecProfile` limiting `VideoRangeType` to `EqualsAny SDR|HDR10|HLG`.
A `NotEquals DOVI` condition is not enough: the server turns it into a range list that still
contains every DV variant and then copies the P5 colours unconverted (green/pink picture).
The returned `TranscodingUrl` (+ `PlaySessionId`) is played as a non-seekable network source.
- Rejected: HLS – would need an HLS-capable network stack in FFmpeg or our own playlist reader.

### Seeking in a transcode = restart with an offset
The progressive stream cannot be seeked. `PlayerEngine` keeps a `timelineOffset` for
transcodes: a seek stops the session, deletes the server's active encoding
(`DELETE /Videos/ActiveEncodings?deviceId=&playSessionId=`), requests a new transcode with
`startTimeTicks`, and shows `position = offset + session position` and the item's full duration
(from `RunTimeTicks`). Track changes in a transcode restart the same way.

### Progress reporting
A small `JellyfinPlaybackReporter` owned by the engine for Jellyfin items: `POST
/Sessions/Playing` on start, `/Sessions/Playing/Progress` every 10 s and on pause/seek/track
change (`PositionTicks`, `IsPaused`, `PlayMethod` DirectPlay/Transcode, `PlaySessionId`,
`MediaSourceId`, `AudioStreamIndex`, `SubtitleStreamIndex`), `/Sessions/Playing/Stopped` on
stop, `/Sessions/Playing/Ping` while transcoding. The server marks items played by its own
rule (default 90 %). After stopping, the store refreshes that item's user data so the library
and Home update. Local `resume.*` keys are not used for Jellyfin items.
- Track indices: Jellyfin numbers external subtitle files first and the file's own streams
  after them, FFmpeg numbers only the file's streams from 0. Without external files both are
  equal; with two external files Jellyfin's subrip track 5 is FFmpeg stream 3 (seen on a series
  episode). Fernsy maps by order: the n-th embedded Jellyfin stream is FFmpeg stream n. Direct
  play menus carry FFmpeg ids, transcode menus Jellyfin indices.

### External subtitles
Jellyfin's external subtitle streams (`IsExternal`) are listed next to the embedded ones. Text
formats are fetched as SRT from `/Videos/{id}/{mediaSourceId}/Subtitles/{index}/0/Stream.srt`
and parsed into the engine's cue list; external bitmap subtitles (SUP/IDX) are not offered in
direct play – choosing one switches to a transcode with burn-in.

### Bitmap subtitles in the player
New shim `ffs_decode_bitmap_subtitle` (avcodec_decode_subtitle2 → for each `SUBTITLE_BITMAP`
rect: palette-expanded RGBA buffer, x/y/w/h, plus the codec's display size) → `BitmapCue
{start, end, images [(CGImage, rect in source pixels)], canvas size}`. The engine publishes the
active bitmap cue like text cues; `PlayerScreen` draws it in a canvas scaled to the video's
displayed rect (letterboxing respected). PGS "clear" packets end the previous cue. Works for
any source, so IPTV DVB subtitles appear too (they were dropped before).
- Rejected: server burn-in for embedded bitmap tracks – keeps direct play impossible for a
  third of the library and makes every seek a restart.

### Several text cues at once
The engine shows all active text cues (joined with a line break, ordered by start) instead of
only the newest one.

### Next episode
For episodes the engine knows the next episode (`/Shows/{seriesId}/Episodes?startItemId=…&limit=2`
when playback starts). On `.ended` the player shows an overlay "Next: S2E5 · Title" with a 10 s
countdown, "Play Now" and "Cancel"; the countdown starts the next item through the same path.

### Tests on the user's server
Playback reporting writes to the server (resume, played). Before tests, the complete user data
of the test items is backed up and restored afterwards (memory: Jellyfin write safety); writes
only to fetched films/episodes; no fabricated ids; failure paths are provoked offline or with a
real item whose direct-play URL is altered locally.

## Risks / Trade-offs

- [Progressive mkv transcode] → verified: mkv streams cleanly (H.264 4K, 0 drops), the encoding
  ends with the player; ts is not needed.
- [DV P5 tone-mapping depends on the server] → Jellyfin reads the DV RPU only with a software,
  VAAPI, NVDEC, D3D11VA or VideoToolbox decoder. An Intel server with QSV and "Prefer OS native
  DXVA or VA-API hardware decoders" off decodes with `hevc_qsv`, skips tone-mapping and only tags
  the output bt709 – the picture stays green/pink in every Jellyfin client. Fernsy cannot fix this
  from the client; the server setting must be on.
- [Stream index mapping differs for some files] → verified; fallback mapping.
- [Bitmap subtitle timing for PGS without end time] → end at the next clear/display set, max 10 s.
- [Token in the stream URL] → never logged; same as Jellyfin's own clients do.
- [App Review] → Jellyfin playback is not reachable without a Jellyfin server; the review notes
  will say so (demo server stays Xtream-only).
