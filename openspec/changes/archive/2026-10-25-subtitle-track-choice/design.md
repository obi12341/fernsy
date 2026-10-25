# Design

## Context

See proposal.md for why. `get_subtitles` (from mcp-scene-search) chose by `language`, else the
playing track, else the first text track. `JFMediaStream` already carries `isForced`,
`isDefault`, `isExternal`, `isTextSubtitleStream`, language and titles. `JellyfinClient` sends
every request through one `URLSession` whose request timeout is 20 s.

## Goals / Non-Goals

**Goals:** the assistant chooses the track from complete information; a first extraction does
not fail.

**Non-Goals:** better automatic choice inside Fernsy.

## Decisions

- **Track list in `item_info`, not a new tool.** `item_info` is where the assistant already
  looks at an item, and the list also answers "which languages does it have". Each entry:
  `index`, `language`, `title` (Jellyfin's display title), `forced`, `default`, `external`,
  and for subtitles `text`. `forced` also counts a title that says forced (`MediaNames.titleSaysForced`),
  as the player does. Rejected: a separate `list_subtitles` tool (one more tool for the same
  data), and choosing non-forced tracks by rule (SDH, CC and commentary tracks would still be
  guessed wrong).
- **`get_subtitles(track)`.** `language` is removed. Without `track`: the playing track if the
  item plays with a text subtitle, else the only text track, else an error that lists the text
  tracks (same entries as `item_info`). An index that is not a text track gives an error with
  the list.
- **Longer timeout only for subtitle files.** `subtitleSRT` uses its own request timeout of
  120 s; every other request keeps 20 s, so an unreachable server is still noticed quickly.
  On a timeout `get_subtitles` says the server is still preparing the subtitles. Rejected:
  raising the timeout for all requests (sign-in and library loads would hang for two minutes
  on a dead server).

## Risks / Trade-offs

- [Clients built for `language`] → the tool exists only in nightlies since today; the
  definition change reaches Claude Desktop with the next extension install.
- [Very large remuxes taking over 2 minutes] → the error asks to retry; the server keeps
  extracting and caches the result.
