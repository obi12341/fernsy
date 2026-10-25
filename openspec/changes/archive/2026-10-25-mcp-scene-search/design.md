# Design

## Context

See proposal.md for why. Relevant current state:

- **Tool results.** `MCPServer` wraps whatever an `MCPTools` handler returns (`[String: Any]`)
  as one text content part plus `structuredContent`. There is no image path yet.
- **Video output.** Decoded frames go to `VideoSink` as `CMSampleBuffer`s for the display
  layer, and nothing keeps the last shown picture.
- **Byte sources.** Three readers exist behind `ByteSource`: `FileByteSource` (recordings),
  `BufferByteSource` (`TimeshiftBuffer` readers; the buffer maps wall time to byte offsets and
  allows several readers at once) and `HTTPByteSource` (network, with ranges). `PlaybackSession`
  feeds FFmpeg from them through custom IO.
- **FFmpeg build.** LGPL, decoders, swscale and the mpegts muxer only, no encoders. JPEG
  therefore has to come from ImageIO.
- **Jellyfin.** `JellyfinClient.subtitleSRT` fetches any text subtitle track as SRT (Jellyfin
  converts embedded text subtitles on the server), `SRTParser` turns it into cues, and
  `directStreamURL` gives the original file with range support. `JFMediaStream` carries
  `isTextSubtitleStream`, language and title.
- **Tuners.** `TunerPool.tuner(channelId)` returns the live tuner, and with it the buffer, of
  a channel that plays or records.

## Goals / Non-Goals

**Goals:**
- Find a scene in about four tool calls, without the visible player moving until the final seek.
- No new network connections for live TV, and no new connections at all for single-stream IPTV.
- One frame-grabbing path for files, the live buffer and Jellyfin.

**Non-Goals:**
- Exact-frame accuracy in `frames`. Keyframe accuracy (usually 1–5 s) is enough to search;
  `seek` plus `snapshot` gives the exact picture.
- HDR-correct colours in stills. A recognisable picture is enough.

## Decisions

- **Image results through a reserved key.** A handler that has a picture returns it under a
  reserved key (`"_image": Data`, JPEG). `MCPServer` removes the key, puts an
  `{"type":"image","mimeType":"image/jpeg","data":<base64>}` part before the text part, and
  leaves `structuredContent` without image data. Tools without images are unchanged.
  Rejected: a new return type for every handler (touches all 17 tools for two that need it).
  Also rejected: returning a file path or local URL (the assistant cannot read the Mac's files,
  and the Claude Desktop extension only forwards JSON).

- **`snapshot` reuses the shown frame.** `PlayerEngine.lastPicture` already keeps the image
  buffer of the last enqueued video frame (for the Picture in Picture loading card), so no new
  reference is needed. `snapshot` converts it with Core
  Image (which handles 10-bit and biplanar formats) to a CGImage, scales it to at most 1280 px
  wide and encodes it as JPEG with ImageIO. The position comes from `PlayerEngine` (live:
  `wallTime(of:)`). Rejected: grabbing the window or layer (needs screen recording permission
  and captures controls and subtitles), and decoding the current position again from the source
  (a second connection for IPTV).

- **`frames` is a keyframe grabber on its own FFmpeg context.** A new `FrameGrabber` opens the
  source through the same custom-IO path as `PlaybackSession` but with a fresh `ByteSource`:
  - a new `FileByteSource` for a recording,
  - a new `TimeshiftBuffer` reader for a live buffer,
  - a new `HTTPByteSource` on `directStreamURL` for Jellyfin.

  For each target time it seeks backwards to a keyframe, decodes that keyframe alone (draining
  the decoder, so frame threading needs no further packets), converts it with the existing
  `ffs_frame_to_pixbuf` and Core Image (same path as `snapshot`) to the tile size and records
  the frame's real time. Live: byte offsets from the buffer index, labels from
  `wallTime(of: pts − mux delay)`; files: positions are `pts − start_time`, like the player's. It runs
  off the main actor, one request at a time, and stops after 60 s with what it has. Video
  decoding is software only (one picture per seek; VideoToolbox setup would cost more than it
  saves). Rejected: the user's original idea of `seek` plus screenshot in a loop (hundreds of
  calls, rebuffering on every step, and the player jumps for the user). Also rejected: decoding
  to the exact target time (every tile would decode up to a whole GOP; searching does not need
  it).

- **Live times map through the buffer index.** For live, `from`/`to` are ISO clock times.
  `TimeshiftBuffer.entry(atOrBeforeWall:)` gives the byte offset to start reading from and
  `wallTime(of:)` gives the label for a decoded frame's media time. Without a range the sheet
  spans the oldest to the newest buffered moment. The grabber reads only bytes already
  buffered and never waits at the live edge.

- **One contact sheet, not many images.** Tiles are 320 px wide (height from the aspect ratio)
  in 6 columns, each with its label (h:mm:ss, or HH:MM:SS clock time for live) in a dark box in
  the corner. The sheet is drawn with Core Graphics and encoded as JPEG at about 0.7 quality,
  so 48 tiles stay a few hundred KB. The JSON lists `{index, position | time}` for each tile, so
  the assistant does not depend on reading the labels. Rejected: one image part per still (48
  image parts cost far more context and some clients limit the number of images).

- **Jellyfin `frames` reads the original file.** It uses a direct-stream connection separate
  from playback. Jellyfin has no stream limit, so this does not affect a running Jellyfin
  playback. Rejected: Jellyfin trickplay tiles (only there when the server generates them, low
  resolution, a second code path) and transcoded streams (the server would start a transcode
  for each seek).

- **IPTV films and series are refused in `frames`.** A second connection would break
  single-stream accounts (see the project constraints). The error suggests `snapshot`.
  Rejected: allowing it when nothing plays (a scheduled recording could start meanwhile, and
  the rule would be hard to explain).

- **`get_subtitles` through the server's SRT.** It picks the track by `language` (ISO code or
  part of the title), else the track that plays, else the first text track. It fetches SRT with
  `subtitleSRT` and parses it with `SRTParser`. Cues are returned as
  `{start, end, start_seconds, end_seconds, text}`, filtered by `from`/`to` (seconds or
  h:mm:ss). A whole film is about 1,000–1,500 cues, which is acceptable as one answer. If an
  answer gets larger than that, the instructions tell the assistant to use a range.

- **Instructions describe the flow.** `MCPTools.instructions` gains one sentence: find scenes
  with `get_subtitles` when dialogue describes them, otherwise `frames` coarse to fine, then
  `seek`, and confirm with `snapshot`.

## Risks / Trade-offs

- [4K HEVC from Jellyfin over the network] → each tile reads from a keyframe on (a few MB);
  48 tiles can take several seconds on a LAN. Mitigation: the 60 s budget, a sheet with the
  tiles fetched so far plus a note, and the default of 24.
- [Dolby Vision profile 5 and HDR] → software-decoded stills can show wrong colours
  (profile 5 looks green or purple). Mitigation: accepted for search. `snapshot` uses the
  player's already converted frame where the DV path provides one.
- [Privacy] → stills leave the Mac to the connected assistant. This only happens when the user's
  assistant calls the tools, and the server is off by default and token-protected.
- [Outdated desktop extensions] → Claude Desktop seems to follow the tool list in the installed
  extension's manifest. Existing users only see the new tools after reinstalling the extension
  from Settings → Assistenten. This will be documented, and a separate change will address it.
- [Live buffer trimmed while reading] → the oldest segment can be deleted during a sheet.
  Mitigation: the grabber skips times that are no longer buffered and labels what it got.

## Open Questions

- The exact JPEG quality and tile width may be tuned after the first sheets have been looked at.
  This does not change the tools.
