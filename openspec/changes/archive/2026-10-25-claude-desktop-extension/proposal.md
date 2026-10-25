# Proposal

## Why

Connecting Claude Desktop to Fernsy's MCP server today means copying a JSON entry into
`claude_desktop_config.json` by hand, and it needs Node.js for the `mcp-remote` bridge. Users
asked for something simpler: a connector URL or a plugin.

A connector URL cannot work: Claude's custom connectors are reached from Anthropic's cloud and
need a publicly reachable HTTPS server, while Fernsy's server deliberately listens on 127.0.0.1
only. Claude Desktop's own way to add a local server in one click is a desktop extension
(`.mcpb`): a small bundle the user double-clicks, which Claude installs with a review dialog and
runs with its bundled Node.js.

## What Changes

- Settings › Assistenten gets "Zu Claude Desktop hinzufügen …": Fernsy builds a `Fernsy.mcpb`
  for the current endpoint and access token and hands it to Claude Desktop, which shows its
  install dialog. No config file, no Node.js installation.
- The extension is a tiny stdio-to-HTTP bridge (one JavaScript file without dependencies) that
  forwards MCP messages to Fernsy's local endpoint. When Fernsy is not running or the server is
  off, tools answer with a clear message instead of failing silently.
- The access token is a sensitive setting of the extension, pre-filled by Fernsy. After
  "Neu erzeugen" the user installs the extension again (or pastes the new token in Claude's
  extension settings).
- Without Claude Desktop installed, the button saves `Fernsy.mcpb` where the user chooses.
- The manual JSON entry stays available as a fallback ("Eintrag kopieren").

Out of scope:
- Custom connectors by URL (not reachable from Anthropic's cloud; would need a public server).
- Listing in Claude's directory or a Claude plugin (directory listings for desktop extensions
  are deprecated; plugins target Claude Code and Cowork, not the Desktop chat).
- Claude Code setup (the `claude mcp add` command already works in one step).
- Any change to the MCP server or its tools.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `mcp-server`: the setup requirement offers a one-click Claude Desktop extension instead of
  only a config snippet; new requirement for the extension's behavior.

## Impact

- New `Fernsy/MCP/MCPDesktopExtension.swift` (builds the bundle: manifest, bridge script,
  icon; zipped with `NSFileCoordinator`), bridge script as a bundled resource.
- `Fernsy/Views/LoginView.swift` (`MCPSettingsForm`): button, fallback, texts.
- `Fernsy/Localizable.xcstrings`, `DEVELOPMENT.md`.
