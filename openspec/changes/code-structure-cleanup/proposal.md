# Proposal

## Why

Fernsy grew three apps (Mac, Apple TV, iOS) and two packages in a few weeks, and it shows. Some
files have outgrown one responsibility: `PlaybackSession.swift` has 1,913 lines, the Mac's
`PlayerScreen.swift` 1,532, `AppModel.swift` 1,381, and `LoginView.swift` (804) mostly holds
the settings window. The same non-UI logic exists two or three times: iCloud sync on Mac and
TV, debug switch parsing, resume keys, per-kind playback start, StartBuilder setup, and TV
screens copied into iOS views. Copies have already drifted. iOS's Start refresh ignores
recordings, and Start's input strings needed the same fix in three places. Dead code and stale
catalog entries make it harder to tell what is live. A read-only survey on 2026-10-31 found all
of this with file and line evidence (design.md).

## What Changes

No behavior changes. Every phase builds, passes the tests and is committed on its own.

- **Phase 1: dead code and leftovers.**
  - Remove unused declarations: `JFKind.itemType`, `CloudClient.devSetAccount`, a misplaced doc
    comment in `AppModel`.
  - Remove catalog keys no code uses, including two in the Mac catalog. In the Apple TV
    catalog, also remove the copies that FernsyCore's catalog shadows.
  - Use the `ResumeStore.movieKey`/`episodeKey` helpers instead of strings built by hand.
  - Document the nine debug switches that the code reads but DEVELOPMENT.md does not mention.
- **Phase 2: split large files** into files, types or extensions, without changing logic.
  - `PlaybackSession`: I/O trampolines, live admission, video, audio, monitor, debug faults.
  - The Mac `PlayerScreen`: controls, OSD, overlays, debug hooks, playback start.
  - `AppModel`: debug bootstrap, catalog, visibility, sync.
  - `MCPTools`: `PlayerWindow` moves out.
  - `PlayerEngine`, and the debug hooks of `HTTPByteSource`.
  - `LoginView.swift` becomes `LoginView.swift` plus `SettingsView.swift`.
  - The tvOS-only `DisplayModeController` leaves the iOS target.
- **Phase 3: one copy of shared logic.**
  - iCloud sync rules, debug environment parsing, the item model helpers (resume key,
    subtitle, archive subtitle, Jellyfin ticks) and the per-kind playback start move to
    FernsyCore/FernsyPlayer, where Mac and TV both need them.
  - StartBuilder setup and the Start refresh inputs move into `TVModel`, shared by Apple TV
    and iOS.
  - The non-UI helpers that iOS copied from the TV screens become shared functions.
  - Apple-TV-only wording in code shared with iOS gets a platform-neutral form.

Out of scope:
- **Visible behavior.** Two survey findings change what users see, and they get their own fix
  after this change:
  - The episode label "S1 F2" is hard-coded and not localized, so English shows "F" as well.
  - Mac and Apple TV pick the "next episode" by different rules.
- **The decision for one FernsyCore package** (archived `fernsy-core-package`, decision A). This
  change does not add packages and does not move `HTTPByteSource` into FernsyCore (decision B).
- **Merging the two image pipelines** (Mac `NSImage`/URLCache, TV `UIImage`/disk cache). They
  differ on purpose in caching, so merging them is a design question of its own.
- **Performance work, new tests for untested behavior, and UI changes.**

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. The change sets `skip_specs: true`: specs describe behavior, and this change keeps it.

## Impact

- Code in all three apps and both packages: moves, splits, deletions, shared helpers. Public API
  of FernsyCore/FernsyPlayer grows by the shared helpers and loses the dead declarations.
- `Fernsy.xcodeproj`: the iOS target's membership exceptions, for files that become tvOS-only.
- String catalogs: removed unused keys.
- DEVELOPMENT.md: the missing debug switches.
- Risk: a moved piece behaves differently. Each phase runs the package tests, `scripts/test.sh`,
  the Apple TV and iOS UI tests and a Mac check on the demo server.
