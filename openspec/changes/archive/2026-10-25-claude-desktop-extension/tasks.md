# Tasks

## 1. Extension bundle

- [x] 1.1 Add the bridge script (embedded in `MCPDesktopExtension.swift`; stdin JSON-RPC → POST to `FERNSY_ENDPOINT` with `FERNSY_TOKEN`, ordered responses, clear errors for "not running" and 401); verify with `node index.js` against a running Fernsy (read-only tools; a debug run with `IPTV_MCP=1 IPTV_MCPTOKEN=test` on the demo server, or the user's running app when it may not be relaunched): `initialize`, `tools/list`, `whats_on` answer; with the app quit a `tools/call` returns the "Fernsy is not running" result; with a wrong token the 401 text
- [x] 1.2 Add `Fernsy/MCP/MCPDesktopExtension.swift` (manifest 0.3 from the current endpoint, token and `MCPTools.definitions`, icon, zip via `ditto`, `Fernsy.mcpb` in the temporary directory, cleanup); debug hook `IPTV_MCPBUNDLE=<path>` writes the bundle there; document it in `DEVELOPMENT.md`; verify by unzipping the bundle and running `npx -y @anthropic-ai/mcpb validate manifest.json`, then running the unpacked `server/index.js` like 1.1

## 2. Settings

- [x] 2.1 In `MCPSettingsForm`: "Zu Claude Desktop hinzufügen …" (opens the bundle with Claude Desktop by bundle id, else a save panel), the JSON entry as "Manuell einrichten" fallback, texts about re-adding after a new token; sync `Localizable.xcstrings` with English; verify with `IPTV_TESTSETTINGS=assistants` window screenshots (light/dark) and, via a debug hook that triggers the button action with Claude Desktop "missing" (`IPTV_TESTNOCLAUDE=1`), that the save path is taken (log)

## 3. Integration

- [x] 3.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`
- [x] 3.2 Install the generated bundle in Claude Desktop on this Mac only with the user's OK (it changes their Claude setup): confirm Claude shows the install dialog for "Fernsy" and, after installing, that a chat can call `whats_on` against the user's running Fernsy; otherwise record that 1.1/1.2 cover the bridge and leave the install to the user — Done: the user installs it themselves with the nightly; 1.1/1.2/2.1 cover the bundle (official `mcpb validate`), the bridge (right token against the user's running Fernsy, wrong token, nothing listening) and the save path
