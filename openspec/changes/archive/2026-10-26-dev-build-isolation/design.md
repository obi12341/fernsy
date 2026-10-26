# Design

## Context

Debug and Release builds use the same bundle id `de.mobilistics.fernsy` (all four build
configurations in `project.pbxproj`). Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY = -`)
and sandboxed with the same entitlements. They therefore share:

- the container `~/Library/Containers/de.mobilistics.fernsy/`: defaults, `Application
  Support/Fernsy/<account>/` (catalog cache, EPG, `recordings.json`, `connections.json`),
  caches with the timeshift buffer;
- the keychain service `de.mobilistics.fernsy` (`Support/Keychain.swift`), which holds the
  accounts;
- App Intents, Spotlight and login-item registrations by bundle id;
- `~/Movies/Fernsy` (`Recorder.swift`, real home via `getpwuid`).

The installed app's container shows that this has leaked already. Its defaults hold
`jellyfin.deviceId.debug`, and its Application Support holds account folders of local test
servers (`http___127_0_0_1_8765_…`, `jellyfin-testserver-testuser`). `PlayerEngine.volume`
writes `player.volume` in every build.

Existing debug guards stay: MCP port 52324, Sparkle off without `IPTV_UPDATEFEED`, no login
item, no Spotlight indexing or donations without `IPTV_SIRIINDEX`, a separate Jellyfin device
id, `FERNSY_NO_KEYCHAIN` with `IPTV_SERVER`, settings in memory (`debugSettingsInMemory`).

## Goals / Non-Goals

**Goals:**
- Isolation that holds even when a debug run forgets an environment variable.
- Debug runs that the user does not hear or see unless they ask for it.
- A safe way to test with a copy of the user's data.

**Non-Goals:**
- Cleaning the installed app's container of old debug leftovers. That would write to the
  user's data. It can be offered separately and done only with the user's consent.
- Making debug builds look like the installed app in Shortcuts or Siri.

## Decisions

### A. Separate bundle id per configuration, same product name

The Debug configurations of both targets (`Fernsy` and `Fernsy Direct`) set
`PRODUCT_BUNDLE_IDENTIFIER = de.mobilistics.fernsy.dev`,
`INFOPLIST_KEY_CFBundleDisplayName = "Fernsy Dev"` (the Info.plist is generated, so no plist
edit is needed) and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Dev`. `CFBundleName` follows
`PRODUCT_NAME` and stays "Fernsy" (menu bar title); Dock and Finder show the display name.
`PRODUCT_NAME` stays `Fernsy`, so the binary path `build/dd/.../Fernsy.app/Contents/MacOS/Fernsy`
and all helper scripts stay valid. Running processes are still told apart by path
(`/Applications/Fernsy.app` against `build/…`).

A new bundle id gives the debug build its own container, defaults domain and system
registrations, without any code. The keychain is separated in code as well: in DEBUG,
`Keychain.service` becomes `de.mobilistics.fernsy.dev`. An ad-hoc signed app would otherwise
still find the installed app's items by service name and trigger an access prompt.

Rejected: a second Xcode target "Fernsy Dev". It would duplicate build phases (FFmpeg
embedding, Sparkle) and drift from the real targets. Rejected: changing `PRODUCT_NAME`. It
would break every path in scripts and helpers for no benefit.

`AppIcon-Dev` is the normal icon with an orange "DEV" band, made once from the existing PNGs
with a small script (`scripts/make-dev-icon.swift`, AppKit drawing like `make-icon.swift`). The icon can then be
regenerated when the real icon changes.

### B. Recordings folder

In DEBUG, `Recorder`'s folder is `~/Movies/Fernsy Dev`. The movies entitlement covers it.

### C. Quiet by default

- `PlayerEngine` starts with `isMuted = true` in DEBUG unless `IPTV_SOUND=1`. The volume
  setter does not write `player.volume` in DEBUG; it reads the stored value of the dev domain
  only.
- A helper `AppActivation.bringToFront()` replaces the direct `NSApp.activate()` calls
  (`MenuBar`, `Recorder` prompts, `MCPTools`, `PlayerScreen`) and the player's
  `orderFrontRegardless` repeats from `player-front-from-assistant`
  (`AppActivation.orderFrontRegardless`). In DEBUG without `IPTV_ACTIVATE=1`, both do
  nothing. A window of an inactive app opens and orders in behind the active app's windows on
  its own, so no `orderBack` is needed. `scripts/dev-run.sh` starts the app with `open -g`, so
  the launch itself does not activate it either. Window screenshots by window id
  (`CGWindowListCreateImage`) work for windows behind others, which is how tests look at
  them.
- Full screen in a debug run (`IPTV_TESTFS`) still creates a Space and switches to it. That
  test stays one the user is asked about first, as today.

Rejected: muting through the system (per-app volume). macOS has no per-app volume API.

### D. Demo-server guard

When a debug build is about to open a stream (live tuner, film, episode, catch-up), it
checks the account's server host. Anything other than `fernsy-demo.mobilistics.workers.dev`,
`127.0.0.1` or `localhost` (local test servers, the demo worker run locally) is refused
unless `IPTV_ALLOWREAL=1`. The check sits in `PlaybackSession` before the input is opened
(`PlayerError.debugAllows`), which covers the tuner, films, episodes and catch-up through one
place, and it matches Xtream stream paths (`/live/`, `/movie/`, `/series/`, `/timeshift/`),
so Jellyfin and local files pass. The refusal shows the normal error card with "Debug-Build:
echte Anbieter nur mit IPTV_ALLOWREAL=1" and logs an error. Catalog and EPG API calls stay
allowed, because they do not take a stream slot.

Jellyfin is not covered by this guard. It has no stream limit, and the existing rule (only
the local Docker test server) is about writes, which `jellyfin-write-safety` covers.

### E. Copying production data: `scripts/dev-copy-prod.sh`

The script reads from `~/Library/Containers/de.mobilistics.fernsy/Data/` and writes to the
dev container `~/Library/Containers/de.mobilistics.fernsy.dev/Data/` (created by one launch of
the dev build; the script says so if it is missing).

- `Application Support/Fernsy/<folder>/` for the chosen account folder. `--list` numbers the
  folders and shows only the beginning of each name (the server), because the names end with
  the account's username. `--account <n>` copies folder n as `copied-<n>`, so the username
  does not appear in commands or logs either. In the copy, `recordings.json` has every
  `scheduled` or `recording` entry set to `skipped`, with the error "Kopie aus Fernsy". This
  is done with `python3 -I` on the copy, never on the original.
- Defaults: the keys for library, live, tracks, recording padding and appearance, through
  `defaults export` from the original and `defaults import` into the dev domain. It never
  copies `mcp.*`, `jellyfin.deviceId*`, `SU*`, `updates.*` or `resume.*` of other accounts.
- No keychain items. The original container is opened read-only (`cp -R` from it, nothing
  written).

Accounts live in the keychain, so a copied account folder has no account to sign in with. A
debug switch `IPTV_COPIEDACCOUNT=<folder>` opens such a folder as an offline account (server
`http://copied-account.invalid`, the folder name as account key; `XtreamClient` throws before
building any API URL for it). It shows
the cached catalog, EPG and recordings list, makes no API calls for it, and refuses streams
like the demo-server guard. This is the only way copied data is used. The user's
credentials never reach the debug build.

Rejected: copying keychain items. That would put the user's provider credentials into a build
that can stream. Rejected: reading the installed app's container live from the debug build.
That would need a temporary exception entitlement, and an accidental write would land in the
user's data.

### F. `scripts/dev-run.sh`

Runs `taskpolicy -b xcodebuild … -derivedDataPath build/dd build`, so the build runs at
background priority and the user's (often software-decoded) playback keeps the CPU. It then
starts the dev binary in the background with the base demo environment (`FERNSY_NO_KEYCHAIN=1`,
demo server, `IPTV_MCP=1`, `IPTV_MCPTOKEN=test`, `-ApplePersistenceIgnoreState YES`). Extra
`KEY=value` arguments are passed through, and the log path is given with `--log <file>`. It
prints whether the installed Fernsy runs (`pgrep -fl /Applications/Fernsy.app`), as a
reminder for tests with real providers. The isolation itself no longer depends on it.

## Risks / Trade-offs

- [Ad-hoc signed dev build with a new bundle id loses the container on signature changes] →
  macOS keys the sandbox container to the bundle id and asks once when the signature changes.
  The dev container only holds test data.
- [Tests that rely on the installed app's container contents (old demo account folders,
  Jellyfin test device)] → the first dev run starts empty. `dev-copy-prod.sh` covers what is
  needed, and the demo account is filled from the demo server on its own.
- [Siri and Shortcuts list "Fernsy Dev" actions next to "Fernsy"] → debug builds already
  neither index nor donate. App Shortcuts are still registered by bundle id. Their phrases
  name "Fernsy Dev" through the display name, so Siri does not confuse them.
- [`orderBack` hides a window a test needs to interact with] → tests talk to the app through
  MCP and environment switches, not by clicking, and window screenshots work behind other
  windows.

## Migration Plan

Nothing migrates. The installed app's container stays as it is, including the old debug
leftovers. After the change, the developer's helpers (`jfrun.sh` and the demo env) point at
the dev container, for example for `recordings.json` backups in
`~/Library/Containers/de.mobilistics.fernsy.dev/...`.
