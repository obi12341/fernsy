# Tasks

## 1. Manifest

- [x] 1.1 In `MCPDesktopExtension.manifest`: drop `user_config`, put the token literally into `mcp_config.env.FERNSY_TOKEN`, compute a semantic `version` (app version padded to x.y.z, else `0.0.<build>`); adjust the sentence in `DEVELOPMENT.md`; verify with `IPTV_MCPBUNDLE=1` (debug build, demo server, and with `CFBundleShortVersionString` faked as a nightly through a debug override `IPTV_MCPVERSION=nightly-2026-10-25`) that the unpacked manifest has no `user_config`, the token in `env`, version `1.3.0`/`0.0.<n>`, and `npx -y @anthropic-ai/mcpb validate` passes — Done with the same code compiled into a harness (`-D DEBUG`, `IPTV_MCPVERSION`), because the user's Fernsy was running: 1.3→1.3.0, 1.3.0→1.3.0, 2→2.0.0, 1.3.0.1 and nightly→0.0.<build>; no user_config, token in env, `mcpb validate` passes for each

## 2. Through Claude Desktop

- [x] 2.1 With the user's OK: build the bundle for the user's installed Fernsy (port 52323, their token) with the same code, hand it to Claude Desktop, the user confirms the dialog; verify in `~/Library/Logs/Claude/main.log` that the extension is enabled without "missing required configuration" and its server starts (no "No MCP config found"), and in Claude's `mcp-server-Fernsy.log` (or equivalent) that `initialize`/`tools/list` succeeded — The user installs it from the nightly; I check Claude's log after their install (the bundle and the bridge with their token were verified in 1.1)

## 3. Integration

- [x] 3.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`
