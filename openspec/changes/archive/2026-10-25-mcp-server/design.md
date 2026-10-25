# Design

## Context

Everything the tools need already lives in the running app on the main actor: the catalog and
visibility rules (`AppModel.filteredChannels`, hidden/adult checks, `recentChannels`, resume
positions), the guide per channel (`EPGStore`, fetched per channel from the provider with a
concurrency limit and an on-disk cache), Jellyfin's `resume`/`nextUp` (`JellyfinStore`), and
recordings with their planning rules (`Recorder.schedule(_:on:)` → `PlanResult`, `delete`).
Fernsy is sandboxed with `network.client` only, and recordings already require the app to run.

MCP clients reach local servers in two ways: Claude Code and other clients speak Streamable
HTTP directly; Claude Desktop starts local servers over stdio from its config file, and a
generic bridge (`npx mcp-remote <url> --header …`) connects that to an HTTP server.

## Goals / Non-Goals

**Goals:**
- One server inside the app, using the app's live state and rules, no second process.
- Safe by default: off, loopback only, token, no browser access.

**Non-Goals:**
- Notifications/streaming (server-sent events), resources or prompts; tools are enough.
- Running without the app.

## Decisions

- **In-app Streamable HTTP server on 127.0.0.1** (Network.framework `NWListener`, a small
  HTTP/1.1 parser, `POST /mcp` with JSON-RPC 2.0, JSON responses; `GET` → 405 since no SSE is
  offered; `DELETE` → 405). Needs `com.apple.security.network.server`.
  Rejected: a stdio helper executable inside the bundle that Claude Desktop starts (an embedded
  tool launched by another app cannot inherit Fernsy's sandbox and would need its own container
  and IPC to the app; much more code and App Review surface), and an XPC service (MCP clients
  cannot speak XPC).
- **Own minimal MCP layer** (`initialize` with protocol version negotiation, `notifications/
  initialized` → 202, `ping`, `tools/list`, `tools/call`; tool input schemas as JSON Schema).
  Rejected: the official Swift MCP SDK as a dependency (its server side targets stdio; the
  HTTP server transport would still be ours, and a new package adds update and license review
  for a few hundred lines of protocol).
- **Fixed port 52323** (debug builds 52324), shown in Settings; if it is taken, Settings shows
  the error. Rejected: a random port (the client config would break on every launch).
- **Access token**: 32 random bytes, base64url, stored in the keychain like the account
  credentials; checked in constant time on every request. Requests with an `Origin` header are
  rejected (403) and the `Host` must be `127.0.0.1:<port>` or `localhost:<port>`, against DNS
  rebinding from websites. Debug builds keep the token in memory (`IPTV_MCPTOKEN`) and never
  touch the keychain.
- **Tools run on the main actor** and reuse the app's functions, so visibility, adult rules and
  planning are identical to the UI. Results are JSON text content (plus `structuredContent`);
  times ISO 8601 with offset; channels by id and name; shows by a stable id
  `<channel>:<start epoch>` that `schedule_recording` accepts.
- **`search_program` is bounded**: the provider delivers the guide per channel, so a search over
  all channels would mean thousands of requests. It searches the given channel ids, or by default
  favourites plus recently watched, at most 50 channels, through `EPGStore` (cache first, the
  existing request limit), and returns which channels it searched so the assistant can widen the
  scope explicitly.
  Rejected: an index of the whole guide (the provider has no bulk EPG in the Xtream API we use;
  XMLTV import is a separate topic).
- **Settings tab "Assistenten"** with: switch, status (running/port taken), address, token with
  copy/regenerate, snippets for Claude Code (`claude mcp add --transport http fernsy
  http://127.0.0.1:52323/mcp --header "Authorization: Bearer …"`) and Claude Desktop (JSON with
  `npx -y mcp-remote … --header`, noting it needs Node.js). The token is inserted into the
  snippets only when the user copies them.
- **Playback reuses the app's start paths** (`AppModel.play(_:)` for channels, films, episodes,
  Jellyfin items and recordings), so window handling, PiP, resume positions and Jellyfin
  progress reports behave as in the UI. Items are addressed by the ids the read tools return
  (`live:<id>`, `movie:<id>`, `episode:<series>:<id>`, `jellyfin:<id>`, `recording:<uuid>`).
  When `recordingsBlocking` finds a running recording that the new channel would end, `play`
  returns `blocked` with the app's explanation and changes nothing. Rejected: showing the app's
  "Aufnahme beenden und umschalten?" prompt (the user may not be at the Mac, and the tool call
  would hang until someone answers) and stopping the recording (a recording must never end
  because of a chat request without the user seeing it). `play` brings the player to the front
  but does not activate Fernsy over another app in full screen.
- **Write tools are limited to recordings and playback** (`schedule_recording`, `cancel_recording` for
  status `scheduled`), each logged under a new `mcp` log category with the client's name from
  `initialize`. MCP clients ask the user before tool calls; Fernsy does not add its own prompt.

## Risks / Trade-offs

- [The assistant starts playback while the user's account is busy elsewhere (another device
  uses the only stream)] → the provider rejects the connection and the player shows its usual
  error; `play` returns once the item is handed to the player, `now_playing` shows the state.

- [Any local process with the token can schedule recordings] → token in the keychain, loopback
  only, server off by default, regenerate button; scheduling is reversible and visible.
- [App Review questions `network.server`] → review note; the feature is opt-in and loopback.
- [Claude Desktop needs Node.js for the bridge] → documented in Settings; a `.mcpb` desktop
  extension can follow later without changing the server.
- [Large guide requests slow the app] → per-call channel cap, cached guides, the EPG store's
  existing concurrency limit; tool calls are async and never block the UI.
- [The server stops when Fernsy quits] → Settings says so; launch-at-login helps.
