# Design

## Context

`AppLog.shared` keeps the current run in memory (`entries(after:)`) and reads the previous run
from `previous.log` (`previousRun()`); entries are redacted when they are added. The player's
`PlayerEngine.stats` (`PlaybackStats`) holds buffer, bitrate, drops, decode failures, rebuffers,
seamless reconnects with the last reason and time, restarts, codec, resolution, frame rate,
decoder and play method; `AppModel.playerEngine` (weak) already gives MCP access to the engine.

## Goals / Non-Goals

**Goals:**
- Enough facts for an assistant to explain stutter, freezes and failures.
- Bounded output: assistants get a filtered slice, not megabytes.

**Non-Goals:**
- A diagnosis engine in Fernsy; the assistant interprets.

## Decisions

- **`get_log` filters in Fernsy**: minimum level (`error` < `warning` < `info` < `detail`,
  default `info`), `category` (the `LogCategory` raw values), `minutes` (default 30; ignored for
  the previous run, which is returned from its end), `query` (case-insensitive substring),
  `limit` (default 200, max 1000; the newest entries within the filter, returned oldest first).
  Output per entry: ISO time, level, category, message; plus `truncated` and the run.
  Rejected: returning the whole file (up to 4 MB) and letting the assistant search.
- **`playback_diagnostics`** returns `now_playing`'s item and state, `PlaybackStats` fields with
  units (`buffer_seconds`, `bitrate_mbps`, `dropped_frames`, `decode_failures`, `rebuffers`,
  `seamless_reconnects`, `last_reconnect_reason`, `last_reconnect_at`, `restarts`, `startup_seconds`,
  `video_codec`, `resolution`, `frame_rate`, `decoder`, `dynamic_range`, `play_method`) and the
  warnings/errors of the last 10 minutes from `player`, `network`, `tuner`, `timeshift`. Without an
  open player it says so and still returns those recent entries.
- **Privacy**: entries are already redacted at the source (app-log requirement), so the tools add
  no new data. The Assistenten footnote says assistants can read the log; the App Review note
  mentions it. The app-log spec names the local MCP server as the only outside reader.

## Risks / Trade-offs

- [The assistant forwards log lines to its cloud model] → the user's choice when switching the
  server on (footnote); lines carry no credentials (redaction self-test `IPTV_LOGSELFTEST`).
- [Very chatty detail level] → default level info and the limit keep answers small.
