# Tasks

## 1. Image results and snapshot

- [x] 1.1 `MCPServer`: a handler value with `"_image"` (JPEG `Data`) becomes an image content part before the text part, and the key is dropped from text and `structuredContent`; verify with the debug build (`IPTV_MCP=1 IPTV_MCPTOKEN=test`, port 52324) and a test client that prints the content part types and the image size
- [x] 1.2 `snapshot` tool (reuses `PlayerEngine.lastPicture`) (definition, handler) converts it with Core Image, scales it to ≤1280 px and encodes JPEG with ImageIO, with position or clock time; verify on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo) for `live:101` (also after `seek by_seconds -60`, clock time matches `now_playing`) and `movie:500`, view the saved JPEGs, and check the error with nothing playing

## 2. Frames

- [x] 2.1 `FrameGrabber`: own FFmpeg context over a fresh `ByteSource`, backward seek to a keyframe, decode it alone, `ffs_frame_to_pixbuf` + Core Image to the tile size, real frame time; contact sheet with labels (Core Graphics) and JPEG (ImageIO); 60 s budget; verify on a finished demo recording (schedule one with the existing recording test client against the demo server, `IPTV_MAXCONN=1`): `frames` without range and with a 1-minute range returns sheets whose labels rise evenly and match `seek to_position` + `snapshot` at two of the times
- [x] 2.2 Live buffer: `item_id live:<id>` reads a new `TimeshiftBuffer` reader, `from`/`to` as clock times, wall-time labels, no read past the buffered end; verify with `live:101` buffered ≥3 min on the demo server with `IPTV_MAXCONN=1`: the sheet spans the buffer, the log shows no new tuner or connection, playback continues without a stall, and a channel that is not tuned gives the "no buffer" error
- [x] 2.3 Running recording and refusals: `frames` on a recording that is still recording covers the recorded part; IPTV `movie:`/`episode:` items return the stream-limit error that suggests `snapshot`; verify both on the demo server

## 3. Jellyfin

- [x] 3.1 Local test Jellyfin: a Docker `jellyfin/jellyfin` container on 127.0.0.1 with a generated test film (the image's bundled ffmpeg: test pattern with a burned-in timecode, a German SRT sidecar plus an embedded English text track, and a film without subtitles; a PGS-only film was not generated, the image-only error is covered by code review only); the debug build signs in with `JF_SERVER`/`JF_USER`/`JF_PASS` against it only (never the user's server); verify that the library shows the film
- [x] 3.2 `frames` for `jellyfin:<id>` over a separate direct-stream connection; verify against the test Jellyfin: the burned-in timecodes on the tiles match their labels within the keyframe distance, also while the same film plays (playback continues)
- [x] 3.3 `get_subtitles` (track choice by `language`/playing track/first text track, `from`/`to`, track list, errors for image-only/none/non-Jellyfin); verify against the test Jellyfin: the German sidecar in full, the English embedded track by `language: "eng"`, a 2-minute range, and the error cases

## 4. Integration

- [x] 4.1 Server instructions describe the find-a-scene flow; `DEVELOPMENT.md` lists the new tools and the reinstall note for the desktop extension; README assistant bullet mentions finding scenes; verify the `initialize` answer and that the generated `.mcpb` manifest lists the three tools (mcpb harness)
- [x] 4.2 End-to-end on the demo server and the test Jellyfin: run a scene search myself through the test client against the debug build (frames coarse, frames fine, `seek`, `snapshot`), view the returned images, and confirm the scene is found in at most four calls
- [x] 4.3 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`

## Workflow follow-up

- After the nightly is installed: the user reinstalls the desktop extension; read-only check of `get_subtitles` and `frames` on a film from the user's own Jellyfin via the release MCP server (port 52323).
