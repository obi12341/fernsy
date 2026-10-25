# Tasks

## 1. Tools

- [x] 1.1 Add a filtered read to `AppLog` (level, category, since, query, limit, current/previous run) and the MCP tool `get_log`; verify on the demo server (`IPTV_MCP=1 IPTV_MCPTOKEN=test`): level warning returns only warnings/errors, category `catalog` only catalog lines, `query` filters, `limit` keeps the newest, `run: previous` reads the last run; with `IPTV_TESTNET=drop:…` a reconnect warning appears; a stream start line shows "•••" instead of the demo credentials — Done: level warning returns only warnings, category catalog only catalog lines, query "reconnect" only matching lines, limit 3 keeps the newest with truncated=true, run previous reads the last run; 42 entries without "demo" credentials, 4 with "•••" (the redaction also masks the username inside the account folder name, as before); level names in the output now match the filter ("warning", not "WARN")
- [x] 1.2 Add `playback_diagnostics`; verify while channel 101 plays with `IPTV_TESTNET=stall:…` (rebuffer) and `drop:…` (reconnect): counts, last reconnect reason and the matching warnings are returned; without a player it reports no playback and the recent entries — Done: live 101 with IPTV_TESTNET drop:12,stall:25 → seamless_reconnects 2, last reason "no data for 5 s, 3.8 s buffered" with time, buffer, codec, resolution, decoder, and the two network warnings; without a player: playing false, a note, recent warnings

## 2. Settings and docs

- [x] 2.1 Extend the Assistenten footnote (assistants can read Fernsy's log), sync `Localizable.xcstrings` with English, update `DEVELOPMENT.md` and the App Review note in `docs/app-store.md`; verify with `IPTV_TESTSETTINGS=assistants` (window screenshot) — Done: footnote in Settings › Assistants (screenshot), English added, DEVELOPMENT.md and the App Review note updated

## 3. Integration

- [x] 3.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`
