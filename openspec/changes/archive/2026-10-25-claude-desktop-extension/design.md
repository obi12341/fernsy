# Design

## Context

Fernsy's MCP server (`Fernsy/MCP/`) speaks Streamable HTTP on 127.0.0.1 with a bearer token.
Claude Code connects to it directly. Claude Desktop starts local MCP servers only as stdio
processes: today through a config entry running `npx mcp-remote` (needs Node.js, hand-edited
JSON). Claude Desktop also installs desktop extensions (`.mcpb`, manifest spec 0.3): a zip with
`manifest.json` and a server, installed by double-click with a review dialog; `server.type:
"node"` runs on the Node.js that ships with Claude Desktop; `user_config` entries become a
settings form, `sensitive` strings are kept in the OS secure storage.

## Goals / Non-Goals

**Goals:**
- One click from Fernsy's Settings to Claude Desktop's install dialog, no other software.
- No change to the server: the extension is a client of the existing endpoint.

**Non-Goals:**
- Remote access, directory listing, signing the bundle.

## Decisions

- **A desktop extension built by Fernsy at click time**, not a static file in the repo or on
  the website: the endpoint (release port 52323, debug 52324) and the token are filled in, so
  the user confirms one dialog and is done.
  Rejected: custom connector URL (Anthropic's cloud cannot reach 127.0.0.1; it would need a
  public HTTPS endpoint, against the loopback-only decision of mcp-server), a Claude plugin
  (aimed at Claude Code/Cowork; directory listing for local servers needs review and gains
  nothing for one user's local app), and keeping only the JSON entry (the complaint).
- **Bridge in plain JavaScript without dependencies** (`server/index.js`, ~80 lines): reads
  newline-delimited JSON-RPC from stdin, POSTs each message to the endpoint with
  `Authorization: Bearer <FERNSY_TOKEN>`, writes non-empty responses to stdout, one at a time in
  order. Connection refused → for requests with an id, a JSON-RPC error and for `tools/call` a
  tool result with `isError` and the text "Fernsy is not running or its MCP server is off …";
  HTTP 401 → "The access token was changed in Fernsy; add Fernsy to Claude Desktop again."
  Uses Node's built-in `fetch` (Node ≥ 18, declared in `compatibility.runtimes`).
  Rejected: bundling `mcp-remote` (megabytes of dependencies, SSE/OAuth logic we do not need)
  and a native binary server (`type: "binary"` would need signing/notarizing a second
  executable inside the bundle).
- **Manifest**: `manifest_version "0.3"`, `name "fernsy"`, `display_name "Fernsy"`, version =
  app version, author mobilistics GmbH, icon from the app icon (512 px PNG),
  `compatibility.platforms ["darwin"]`, `server.mcp_config` with `command "node"`,
  `args ["${__dirname}/server/index.js"]`, `env { FERNSY_ENDPOINT, FERNSY_TOKEN:
  "${user_config.access_token}" }`; `user_config.access_token` = string, sensitive, required,
  default = current token. The tool list is declared from `MCPTools.definitions` (names and
  descriptions) so the install dialog shows them.
- **Packing**: write the files to a temporary folder and zip its contents with `/usr/bin/ditto
  -c -k --norsrc` into `Fernsy.mcpb`. Rejected: `NSFileCoordinator` `.forUploading` (it puts the
  folder itself at the archive root, so `manifest.json` would not be at the root as MCPB
  requires) and an own zip writer (more code for no gain). The bridge script is a string in
  `MCPDesktopExtension.swift`, not a separate resource, so it cannot go missing from the bundle. **Opening**: `NSWorkspace.open([url], withApplicationAt: Claude.app)` found by
  bundle id `com.anthropic.claudefordesktop`; if missing, an `NSSavePanel`
  (user-selected file entitlement exists). Works in the sandbox: the file lives in the app's
  temporary directory and is handed over by Launch Services.
- **The JSON entry stays** behind a smaller "Manuell einrichten" fallback, because Claude
  Desktop versions without extension support exist and admins may block extensions.

## Risks / Trade-offs

- [The token sits in the bundle file as a default] → the file is written to the app's temporary
  directory and deleted after 10 minutes / on next launch; a saved copy is the user's choice.
- [Claude Desktop changes the extension format] → manifest 0.3 is current; validated with the
  official `mcpb validate` in the tasks.
- [Token regenerated] → extension gets 401 and says what to do; re-adding replaces it (same
  `name`).
