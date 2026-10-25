# Tasks

## 1. Server and protocol

- [x] 1.1 Add `network.server` to both entitlements files; add `Fernsy/MCP/MCPHTTPServer.swift` (NWListener on 127.0.0.1, HTTP/1.1 POST /mcp, 405 for GET/DELETE, Host/Origin checks, bearer token, body limit); verify with a debug run (`IPTV_MCP=1 IPTV_MCPTOKEN=test`, demo server) and `curl` that a request without token gets 401, with `Origin` 403, from the LAN address no connection
- [x] 1.2 Add `Fernsy/MCP/MCPServer.swift` (JSON-RPC 2.0, `initialize`/version negotiation, `notifications/initialized`, `ping`, `tools/list`, `tools/call`, errors); verify `initialize` and `tools/list` with `curl` against the debug run
- [x] 1.3 Token: keychain in release builds, in memory in debug builds (`IPTV_MCPTOKEN`), regenerate invalidates at once; log category `mcp`; document `IPTV_MCP`, `IPTV_MCPTOKEN` in `DEVELOPMENT.md`; verify regenerate with two `curl` calls (old token 401 after regenerate via a debug hook)

## 2. Tools

- [x] 2.1 `find_channels`, `whats_on`, `get_program` with the app's visibility rules; verify with `curl` against the demo server, and with `IPTV_TESTADULT=<id>` that an adult channel is not returned while adult content is off
- [x] 2.2 `search_program` (given ids, default favourites + recent, max 50, lists searched channels); verify with `IPTV_RECENT=<ids>` and a title from the demo guide
- [x] 2.3 `recently_watched` (live, IPTV resume positions, Jellyfin resume/next up); verify with `IPTV_RECENT` and `IPTV_TESTRESUME` on the demo server; Jellyfin part only against `http://127.0.0.1:9` (empty/offline result, no error)
- [x] 2.4 `list_recordings`, `schedule_recording`, `cancel_recording` through `Recorder`; verify with `IPTV_MAXCONN=1` on the demo server: schedule a show (appears in the Recordings list, window screenshot), schedule an overlapping one on another channel (refused), cancel the first, cancel a finished one (error, file untouched); restore the demo account's `recordings.json` afterwards

- [x] 2.5 `play`, `now_playing`, `stop_playback` through `AppModel.play(…)`; `play` returns `blocked` when `recordingsBlocking` finds a recording; verify on the demo server: play channel 101, then 102 (switches; window screenshot), play a demo film and a recording (`IPTV_SCENE` not needed), `stop_playback`; with `IPTV_MAXCONN=1 IPTV_TESTRECORD=101:5:120` play 102 → `blocked`, recording continues (log); restore `recordings.json`, trash test files

## 3. Settings

- [x] 3.1 Settings tab "Assistenten" (switch, status, address, token copy/regenerate, Claude Code and Claude Desktop snippets, note that Fernsy must run); `SettingsTab.assistants`, `IPTV_TESTSETTINGS=assistants`; sync `Localizable.xcstrings` with English; verify with window screenshots in light and dark (`IPTV_APPEARANCE`)

## 4. Integration

- [x] 4.1 End-to-end with Claude Code without touching the user's config: `claude -p --strict-mcp-config --mcp-config <scratch json>` against the debug run asks "what's on now on channel 101", "schedule the next show on 101" and "switch to channel 102"; verify the answer and the scheduled recording, then restore `recordings.json`
- [x] 4.2 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`; add the App Review note to `docs/app-store.md`; the README (product page) gets the feature with the release that ships it, since it may only claim what the current release does
- [x] 4.3 Claude Desktop path without touching the user's config: run `npx -y mcp-remote http://127.0.0.1:52324/mcp --header "Authorization: Bearer test"` against the debug run and send `initialize` and `tools/list` over its stdio; verify both answer (skip with a note if Node.js is not installed)
