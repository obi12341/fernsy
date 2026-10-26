# Proposal

## Why

Debug builds share the bundle id `de.mobilistics.fernsy` with the installed app, and with it
the sandbox container (settings, accounts, `recordings.json`, caches), the keychain scope,
Spotlight and App Intents registrations and `~/Movies/Fernsy`. Today the installed app is
only protected by per-feature `#if DEBUG` exceptions and by the developer's discipline. Some
leaks exist already: the debug player stores its volume in the shared defaults. A debug build
started without the demo-server environment would also load the user's account and scheduled
recordings, and could open a second stream that ends the user's playback or recording.
Debug runs can also play sound and take focus while the user watches.

## What Changes

- Debug builds get their own identity: bundle id `de.mobilistics.fernsy.dev`, display name
  "Fernsy Dev" and an app icon with a "DEV" mark. They get their own container, defaults,
  keychain scope and system registrations, and never see the installed app's data.
- Debug recordings go to `~/Movies/Fernsy Dev`.
- Debug builds are quiet by default. They start muted unless `IPTV_SOUND=1`, do not store
  the volume, and do not bring themselves to the front unless `IPTV_ACTIVATE=1`. Their
  windows open behind the app the user is using.
- Debug builds refuse to stream from any server other than the demo server unless
  `IPTV_ALLOWREAL=1` is set. This enforces the single-stream rule in code.
- A script `scripts/dev-copy-prod.sh` copies selected data from the installed app into the
  dev container for tests: account folders (catalog, EPG cache, recordings list), channel and
  view settings. It copies no keychain items, and it turns copied scheduled or running
  recordings into skipped ones, so the dev build never records on the user's behalf. It only
  reads from the installed app's container.
- A script `scripts/dev-run.sh` builds at background priority (`taskpolicy -b`), so the
  user's playback keeps the CPU, and starts the dev build against the demo server with the
  usual debug environment.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `distribution`: a new requirement that development builds are isolated from the installed
  app.

## Out of Scope

- A macOS virtual machine for tests. A VM has no hardware video decoding, so it is not
  representative for playback tests, and it costs about 50 GB.
- Removing the existing per-feature debug guards (separate MCP port 52324, Sparkle off, no
  login item, no Spotlight indexing, separate Jellyfin device, `FERNSY_NO_KEYCHAIN`). They
  stay as a second layer.
- Copying keychain items or Jellyfin access tokens from the installed app.
- Changes to Release, App Store or DMG builds, whose bundle id and behavior stay as they are.

## Impact

- `Fernsy.xcodeproj/project.pbxproj`: Debug configurations of both targets (bundle id,
  display name, app icon).
- `Fernsy/Assets.xcassets`: `AppIcon-Dev`.
- `Fernsy/Recording/Recorder.swift`: recordings folder for debug builds.
- `Fernsy/Player/PlayerEngine.swift`: muted start, volume not persisted in debug.
- `NSApp.activate()` call sites (`MenuBar.swift`, `Recorder.swift`, `MCPTools.swift`,
  `PlayerScreen.swift`) and `PlayerWindow`: one helper that does nothing in quiet debug runs.
- `AppModel` / account loading: the demo-server guard.
- New `scripts/dev-run.sh`, `scripts/dev-copy-prod.sh`; DEVELOPMENT.md section.
- Local helpers in the session scratchpad that point at `build/dd/.../Fernsy.app` keep
  working (the product name stays "Fernsy").
