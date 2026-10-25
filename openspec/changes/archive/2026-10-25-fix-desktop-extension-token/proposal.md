# Proposal

## Why

The Claude Desktop extension from 1.3.x's nightly installs but never connects: Claude shows
"Unable to connect to extension server". Claude Desktop's log says "has missing required
configuration, not enabling automatically" and later "No MCP config found … skipping"; its stored
settings for the extension have an empty `userConfig`. Claude does not take the default value of
a sensitive `user_config` field, so the pre-filled access token never reaches the bridge, and the
bridge process is never started. A second defect: the manifest `version` was the app's display
version, which is `nightly-<date>` in nightlies and not the semantic version the manifest
requires.

## What Changes

- The access token is written straight into the extension's launch environment
  (`mcp_config.env.FERNSY_TOKEN`); the manifest has no `user_config` any more. Claude enables the
  extension right after installing, with nothing to fill in.
- The manifest `version` is always a semantic version: the app version as `x.y.z`, or
  `0.0.<build number>` for nightlies and other non-numeric versions.
- After "Neu erzeugen", adding Fernsy to Claude Desktop again replaces the installed extension
  (same id), as before.

Out of scope:
- Signing the extension.
- Changes to the bridge, the MCP server or its tools.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `mcp-server`: "Claude Desktop extension" no longer keeps the token as a sensitive setting; it
  carries it in the extension and works right after installing.

## Impact

- `Fernsy/MCP/MCPDesktopExtension.swift` (manifest), `DEVELOPMENT.md` (one sentence).
- Users who installed the nightly's extension add Fernsy to Claude Desktop again.
