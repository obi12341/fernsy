# Proposal

## Why

On the user's own Jellyfin, `get_subtitles` without a language picked the first text track,
which on many films is a "forced" track with only a handful of cues (5 for one film, 9 for
another). That is useless for finding a scene, and even `language: "ger"` would have hit the
forced German track first. Picking by rule in Fernsy will keep missing (forced, SDH, CC,
commentary), while the assistant can read the track titles and choose. Separately, the first
request for an embedded track timed out: Jellyfin extracts the track from the whole file
before it answers, which takes longer than the client's 20 s.

## What Changes

- `item_info` for Jellyfin items lists the audio and subtitle tracks: index, language, title,
  and `forced`, `default`, `external` and `text` (text or image) flags.
- `get_subtitles` takes `track` (the index from `item_info`) instead of `language`. Without
  `track` it uses the subtitle track that plays, or the only text track. When there are
  several text tracks, it answers with an error that lists them. **BREAKING** for MCP clients
  that passed `language` (the tool is a few hours old and only in nightlies).
- Subtitle files are fetched with a longer timeout (2 minutes) so the server's first
  extraction finishes. If it still times out, the error says the server is preparing the
  subtitles and to try again shortly. Playback's own subtitle loading uses the same request
  and benefits as well.

### Out of scope

- Image subtitles (PGS) as text.
- IPTV tracks in `item_info`.
- Any change to how the player chooses subtitles.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `mcp-server`: track list in `item_info`; `get_subtitles` track choice by index; timeout message.

## Impact

- `Fernsy/MCP/MCPTools.swift` (`item_info`, `get_subtitles` definition and handler).
- `Fernsy/Jellyfin/JellyfinClient.swift` (`subtitleSRT` with a longer timeout).
- `DEVELOPMENT.md` (MCP notes).
