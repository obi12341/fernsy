# Proposal

## Why

Tested with the nightly (build 124): Siri AI on macOS 27 does not use App Shortcut phrases.
"Schalte Fernsy auf ZDF" got "Die App „Fernsy“ unterstützt diese Anfrage leider nicht", and
"Was läuft gerade in Fernsy?" got "… da die App die Suche innerhalb der App nicht unterstützt".
Siri AI understands the request itself and then looks for an app intent with a matching schema.
The `.system` domain ("System and in-app search") is meant for any app and has two schemas that
fit Fernsy: `open` (open an item) and `searchInApp`. Everything else stays with the MCP server,
as the user decided.

## What Changes

- New intent with the `.system.open` schema whose target is a `ChannelEntity`: "Öffne ZDF in
  Fernsy" plays the channel, with the same recording check as before.
- New intent with the `.system.searchInApp` schema: "Suche Tatort in Fernsy" opens Fernsy's
  library window with the toolbar search filled in (channels, films, series, recordings,
  Jellyfin).
- The App Shortcuts and the other intents stay; they work in the Shortcuts app and Spotlight,
  not by voice with Siri AI. The spec says so instead of promising spoken phrases.

Out of scope:
- "What's on", guide search, recording by voice: no fitting schema; these remain MCP features.
- An experimental "on now" property on channel entities (decided against: no documented way for
  Siri AI to answer from it).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `siri`: "App Shortcut phrases" and "Onscreen context" are removed (their spoken scenarios
  do not hold) and replaced by "Shortcuts and Spotlight actions" and "Onscreen channel for
  actions"; new requirement "Siri AI schemas" for `.system.open` and `.system.searchInApp`.

## Impact

- `Fernsy/Intents/FernsyIntents.swift` (two schema intents), `AppModel` (`requestedSearch`),
  `LibraryView` (applies it, opening the library window if needed), `PlayerWindow` helper.
- `Localizable.xcstrings`, `DEVELOPMENT.md` (`IPTV_TESTINTENT` steps `open:`, `search:`).
