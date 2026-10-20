# Design

## Context

- Video path today: `PlaybackSession.videoMain` opens an FFmpeg decoder with the VideoToolbox
  hwaccel (`ffs_open_decoder(st, 1)`), receives `AVFrame`s, turns them into `CVPixelBuffer`s
  (`ffs_frame_to_pixbuf`, which also copies colour attachments), wraps them in sample buffers
  and hands them to `enqueueVideo` (preroll, clock, buffer stats) → `AVSampleBufferDisplayLayer`.
  FFmpeg's hwaccel always creates its VideoToolbox session as plain HEVC (`hvc1`).
- The overlay already detects DV by `AV_PKT_DATA_DOVI_CONF` in the stream's coded side data
  and shows "Dolby Vision".
- Jellyfin playback transcodes `VideoRangeType == "DOVI"` (profile 5) via
  `JellyfinPlayback.transcodeReason`.
- Spike (scratchpad, Jellyfin's public 1080p DV P5 test file, M4 Max, macOS 27):
  - VideoToolbox session created as `kCMVideoCodecType_DolbyVisionHEVC` from a format
    description holding only the `hvcC` and the 24-byte `dvcC` atoms → pixel buffers carry a
    `DolbyVisionRPUData` attachment (the RPU NAL payload without its 2-byte header) and PQ
    transfer; `AVSampleBufferDisplayLayer` shows correct colours.
  - Same bitstream decoded as plain HEVC → green/pink picture (today's behaviour).
  - Plain HEVC decode with the RPU attached by hand (attachments and IOSurface values identical
    to the DV session's output) → black picture. The layer needs state only a DV session gives.
  - The raw decoded pixels are identical in both sessions: macOS does the DV mapping at display
    time, not in the decoder.

## Goals / Non-Goals

**Goals:** DV profile 5 and 8 from MKV/MP4 shown through Apple's DV pipeline with the existing
player behaviour (preroll, seeking, pause, subtitles, stats); safe fallback when a Mac cannot.

**Non-Goals:** profile 7 enhancement layer, MPEG-TS sources, our own DV maths (see proposal).

## Decisions

### Own VideoToolbox session for DV streams, inside the existing video thread
When the selected video stream is HEVC with a DOVI config record of profile 5 or 8 and the
packets are length-prefixed (extradata is an `hvcC`, i.e. MKV/MP4), `videoMain` decodes with a
`DVDecoder` instead of the FFmpeg decoder:
- format description: codec `dvh1`, extension atoms `hvcC` = stream extradata, `dvcC` = the
  config record serialised to 24 bytes (version, profile/level/rpu/el/bl flags, compatibility
  id, zero padding); dimensions from codecpar;
- each packet becomes a `CMSampleBuffer` over the packet data (no copy beyond a `CMBlockBuffer`
  wrapping), PTS/DTS from the packet, decoded synchronously;
- output pixel buffers are kept as they are (the DV attachments must survive: no
  `ffs_frame_to_pixbuf`, no colour re-tagging) and go through the same `enqueueVideo` path.
- Rejected: attaching the RPU to FFmpeg-decoded buffers – black picture (spike).
- Rejected: enqueueing compressed samples into the layer and letting it decode – works in the
  spike, but bypasses our decode-side preroll, frame stats, dropped-frame counting and the
  session's clock logic that every other stream uses.
- Rejected: patching FFmpeg's VideoToolbox hwaccel to create `dvh1` sessions – a local LGPL
  patch to maintain across FFmpeg updates for a few dozen lines we can own in Swift.
- Rejected: AVPlayer for DV files – a second player engine without our subtitles, stats,
  Jellyfin reporting hooks or timeshift integration.
- Rejected: own reshaping in Metal or libplacebo – more work, not Apple's licensed mapping,
  legal grey zone.

### Frame order
VideoToolbox returns frames in decode order. `DVDecoder` keeps a small reorder queue (size =
the stream's `video_delay`/`has_b_frames` + 1, at least 4) and releases frames in PTS order, so
`present`'s duration and preroll logic see presentation order as with FFmpeg. Flush on seek
empties the queue and calls `VTDecompressionSessionWaitForAsynchronousFrames`; the session
itself is kept across seeks.

### Capability check and fallback
- `VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC)` decides before opening.
- If the session cannot be created, or the first frames fail to decode: profile 8 → FFmpeg
  decoder as today (HDR10 base layer); profile 5 → the session fails with an error "Dolby Vision
  is not supported on this Mac", which Jellyfin playback already turns into a transcode
  (`onFailedBeforeStart`).
- Profile 7 always takes the FFmpeg path (EL ignored, HDR10 base). Rejected for now: rewriting
  the config to profile 8.1 to play the base layer plus RPU as DV – possible later, needs its
  own testing for MEL/FEL files.

### Jellyfin rule
`transcodeReason` returns "Dolby Vision Profil 5" only when
`VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC)` is false.

### Stats
Decoder "VideoToolbox (Dolby Vision)"; dynamic range "Dolby Vision 5" / "Dolby Vision 8.1"
when shown as DV, "Dolby Vision 8.1 → HDR10" or "Dolby Vision 7 → HDR10" when the base layer is
shown; pixel format from the buffer as today.

### Audio in blocks (bug fix found while testing)
TrueHD played silently in every Fernsy build: its frames hold 40 samples (0.83 ms) and the
audio thread enqueued each decoded frame as its own sample buffer – about 1200 buffers per
second. `AVSampleBufferAudioRenderer` reports `rendering`, not muted, but outputs nothing.
AC-3/E-AC-3 (1536 samples) and AAC (1024) were fine. Verified by switching only the buffer size
on the same film: per-frame buffers silent, 20 ms blocks audible (TrueHD 5.1 and 7.1).
- The audio thread now collects resampled PCM into blocks of at least 20 ms; a block ends early
  at a timestamp jump, a format change, a flush (seek) and at the end of the stream.
- MKV stores millisecond timestamps, so consecutive 0.83 ms frames get rounded, duplicated
  timestamps. Deviations under 50 ms from the sample-counted position now follow the sample
  count; larger ones resync. This alone did not bring the sound back.
- Debug: `IPTV_AUDIOLEVEL=1` logs the peak level per channel and the renderer state once per
  second; `IPTV_TESTAUDIO=<at s>:<track>,…` switches audio tracks.

## Risks / Trade-offs

- [Reorder depth guessed wrong → stutter at B-frame pyramids] → size from codecpar plus a
  margin; verify PTS order in a debug log during the test runs.
- [DV session differs between Macs/macOS versions] → capability check plus fallback; the
  overlay shows which path is used.
- [RPU missing in some packets or files with a broken RPU] → VideoToolbox decides; a failed
  start falls back like a failed session.
- [HDR10+ dynamic metadata of profile 8 files] → not used when shown as DV (DV metadata wins);
  unchanged on the fallback path.
- [Thumbnails or screenshots of DV pictures] → screen captures of the layer are what the user
  sees; no extra handling.

## Migration Plan

None; the change is local to the player. Rollback = revert; Jellyfin falls back to transcoding
profile 5 as before.
