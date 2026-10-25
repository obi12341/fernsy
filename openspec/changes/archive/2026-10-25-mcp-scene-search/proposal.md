# Proposal

## Why

Users ask their assistant to find a scene ("go to where they argue on the beach", "show me the
goal again"). Today the assistant can seek but cannot see or read what is in a video. If it
stepped through the film with seek and screenshots, that would take hundreds of round trips and
make the visible player jump around. The assistant needs to look at a stretch of video, or read
its dialogue, without touching the player, and then seek once.

## What Changes

- New MCP tool `snapshot`: the picture the player currently shows, as an image, with its
  position (or clock time for live TV). Works for everything that plays, including IPTV films
  and live TV without timeshift, because it uses the frame already on screen.
- New MCP tool `frames`: a contact sheet, one image with up to 48 evenly spaced stills, each
  labelled with its position (or clock time). It covers a time range of a Jellyfin item, a
  recording, or the timeshift buffer of a tuned live channel. It is read without touching the
  player, so the assistant can narrow down a scene in a few calls (coarse range, then a finer
  one) and then `seek`.
- New MCP tool `get_subtitles`: the text subtitles of a Jellyfin item with start and end times,
  optionally for a time range and a language, so the assistant can find a scene by what is said.
- MCP tool results can carry an image (standard MCP image content) next to the text.
- The server instructions describe the find-a-scene flow: subtitles first when the scene is
  described by dialogue, otherwise `frames` coarse to fine, then `seek`, then `snapshot` to
  confirm.

### Out of scope

- `frames` for IPTV films and series. It would need a second connection to the provider, which
  single-stream accounts do not have. `snapshot` still works for them.
- Subtitles or transcripts for live TV and recordings: no teletext, no OCR of DVB subtitles, no
  speech recognition (decided against for live TV).
- Image subtitles (PGS/VobSub) in `get_subtitles`: only text subtitles are returned.
- Detecting an outdated Claude Desktop extension (users with an older extension reinstall it
  from Settings → Assistenten to get the new tools). This is a separate change.
- Any UI in the app itself. This change only adds assistant tools.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `mcp-server`: adds the scene-search tools (`snapshot`, `frames`, `get_subtitles`) and image
  results.

## Impact

- `Fernsy/MCP/MCPServer.swift` (image content in tool results), `Fernsy/MCP/MCPTools.swift`
  (definitions, handlers, instructions).
- New frame grabber in `Fernsy/Player/`. It reads through the existing byte sources
  (`FileByteSource`, `TimeshiftBuffer` readers, `HTTPByteSource` for Jellyfin direct stream),
  decodes keyframes with the bundled FFmpeg (decoders and swscale only, no encoder), and
  writes JPEG with ImageIO.
- `Fernsy/Player/RendererSinks.swift` / `PlayerEngine.swift`: keep a reference to the last
  shown video frame for `snapshot`.
- `Fernsy/Jellyfin/JellyfinClient.swift`: reuses `subtitleSRT` and `directStreamURL`.
- Claude Desktop extension: its manifest lists the new tools automatically; existing installs
  need a reinstall.
- `DEVELOPMENT.md` (MCP tools), `README.md` assistant bullet (finding scenes).
- Privacy: stills of what the user watches go to the assistant the user connected, only when
  the assistant calls these tools.
