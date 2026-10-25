# Design

## Context

See proposal.md for the failure and its evidence (Claude Desktop 3.6556.2 log and stored
extension settings). The manifest today declares `user_config.access_token` as `string`,
`sensitive`, `required`, with the token as `default`, and maps it into
`mcp_config.env.FERNSY_TOKEN` as `${user_config.access_token}`. Claude Desktop installs the
bundle but leaves `userConfig` empty and does not start the server.

## Goals / Non-Goals

**Goals:**
- Installed = working, with no settings form.
- A valid manifest in every build flavour.

**Non-Goals:**
- Changing how the token is created or rotated in Fernsy.

## Decisions

- **Token as a literal in `mcp_config.env`, no `user_config`.** Claude starts the bridge with
  the environment from the manifest, so the token arrives without any user step.
  Rejected: keeping the sensitive field and asking the user to paste the token (the step the
  extension exists to remove); a non-sensitive `user_config` with default (undocumented whether
  Claude applies defaults there either, and it would show the token in a form anyway); reading
  the token from Fernsy's keychain item in the bridge (another app cannot read Fernsy's keychain
  item without a prompt, and Node has no keychain API).
  Trade-off: the token sits in plain text in Claude's extension folder, like in the manual JSON
  entry; it only opens Fernsy's loopback server on this Mac and is replaced with "Neu erzeugen".
- **Semantic version**: `CFBundleShortVersionString` if it matches `^\d+(\.\d+){0,2}$`, padded to
  three parts; otherwise `0.0.<CFBundleVersion>` (the commit count in CI builds, also numeric).
- **Verification goes through Claude Desktop itself.** The first round tested the bridge with
  the token set by hand, which skipped exactly the part that failed. This time the bundle the
  app builds is installed by Claude Desktop (with the user's OK, replacing the broken install)
  and Claude's log must show the server starting.

## Risks / Trade-offs

- [Token readable by other local processes running as the user] → same exposure as the manual
  config entry; loopback-only server; regenerate in Fernsy if in doubt.
