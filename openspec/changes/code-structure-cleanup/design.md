# Design

## Context

See proposal.md for the motivation. A read-only survey of all Swift sources, tests, scripts and
DEVELOPMENT.md (2026-10-31) found what follows. Line numbers are from that day's `main`.

Layout today: the Mac app (`Fernsy/`, about 13,000 lines), the Apple TV app (`FernsyTV/`,
about 7,900), which the iOS target also compiles except for the files in its membership
exceptions in `Fernsy.xcodeproj`, the iOS views (`FernsyiOS/`, about 4,000), and the packages
FernsyCore (about 6,600, no FFmpeg) and FernsyPlayer (about 8,000, FFmpeg, shared playback).

Recorded decisions this change keeps: one FernsyCore package with one library product, and
FFmpeg-bound code (`HTTPByteSource`, `Recorder`, Jellyfin playback) outside it
(`2026-10-26-fernsy-core-package`, decisions A and B).

### Survey findings

**Dead or unused** (each checked by a repo-wide search including tests and docs):
- `JFKind.itemType` (`Fernsy/Views/JellyfinViews.swift:9`), never used.
- `CloudClient.devSetAccount` (`FernsyCore/CloudClient.swift:190-193`): no Swift caller; the
  endpoint is used through curl and the server tests.
- The doc comment at `AppModel.swift:1100` belongs to `play(jellyfin:)` at :1140.
- `ResumeStore.episodeKey` is never called, while `"episode.\(id)"` is built by hand in about
  ten places (Mac, TV, iOS, MCP) and `"movie.\(id)"` on the Mac in about eight.
- Catalog keys without code:
  - Mac: "New Movies", "New Series".
  - Apple TV: "Loading …", "Server address", and the old one-account note.
  - Apple TV also has "Coming Up" and "Movies · %@", which are shadowed: StartBuilder looks
    them up in FernsyCore's catalog (`bundle: .module`).
- Debug switches the code reads but DEVELOPMENT.md does not name: `IPTV_FAVORITES`,
  `IPTV_GUIDESCROLL`, `IPTV_PLAYURL`, `IPTV_TESTCLOSE`, `IPTV_TESTHOVER`, `IPTV_TESTPADDING`,
  `IPTV_TESTSIGNOUT`, `IPTV_TESTZAP`, `JF_KEYCHAIN_SUFFIX`. No switch is documented but unread.
- Kept on purpose: `CloudByteSource.cachedChunkCount` (used only by tests, and states what it is
  for) and `JFItem.childCount` (a decoded field the server sends; removing it gains nothing).

**Duplicated:**
- iCloud sync: `AppModel.swift:1242-1381` and `TVModel+Sync.swift:9-149` match almost line for
  line, about 110 lines each. They differ in how the IPTV login is done and in what visibility
  state is pulled.
- Debug environment:
  - `debugCredentials` (AppModel:399-409, TVModel:555-564), `skipKeychain`, and
    `IPTV_TESTRESUME` (AppModel:580-588, TVModel:186-195) are each written twice.
  - `IPTV_TESTHIDE` is written twice with different syntax.
  - The library-enlarging loop exists twice inside TVModel (408-427, TVModel+Library 154-178).
- Item model helpers: `PlayItem.resumeKey`/`logDescription` (AppModel:75-98) and
  `VODItem.resumeKey`/`subtitle` (TVModel+Library:36-57). The archive subtitle format appears 7
  times, the tick conversion `/ 10_000_000` 20 times, and `episodeIndex` twice.
- Per-kind playback start: Mac `PlayerScreen.swift:387-427` (in a view) and TV
  `TVModel+Library.swift:251-293`. The Jellyfin start, the cloud source with its failure report,
  and the archive setup are the same code, about 30 lines each.
- StartBuilder setup: Mac `StartView.swift:76-98` and `TVModel+Start.swift:9-28`. The Start
  refresh inputs exist three times; the iOS copy lost the recordings.
- TV screens and iOS views share many identical non-UI lines:

  | Apple TV | iOS | Identical lines |
  |---|---|---|
  | DetailScreens | LibraryViews | 123 (`facts`, `position`, `duration`, entries) |
  | JellyfinSearchScreens | JellyfinSearchViews | 103 |
  | StartScreen | StartView | 95 |
  | ChannelListScreen | LiveTVView | 56 |

**Structure:**
- `PlaybackSession.swift` (1,913 lines) has separable parts:
  - I/O trampolines and `SourceBox` (9-28; `FrameGrabber` also uses them).
  - Multi-connection live admission (166-263, 500-644).
  - Bitmap subtitles (977-1007).
  - Video pipeline (1126-1412; `videoMain` alone is 194 lines).
  - Audio pipeline with `AudioLevelMeter` (1414-1657).
  - Monitor (1658-1805; `tick` is 123 lines).
  - Debug fault injection (1806-1845).
  - `LastPicture` and `PlayerError` (1865-1913).
- The Mac's `PlayerScreen.swift` (1,532 lines): `body` is 285 lines, about 115 of them debug
  hooks. It also holds `PlayerControls`, `ChannelOSD`, the stats overlays,
  `NextEpisodeOverlay` and `BitmapSubtitleView`, and the playback start is model logic inside
  the view.
- `AppModel.swift` (1,381 lines): `debugBootstrap` (419-640, 222 lines), `PlayItem`, the
  catalog cache, visibility and favorites, series track memory, sync.
- `MCPTools.swift`: `enum PlayerWindow` (1002-1070) is window management.
- `PlayerEngine.swift`: `PlaybackProgress`, `BufferHistory` and `ExternalPlayback` (9-123);
  `handle(_:generation:)` is 139 lines.
- `HTTPByteSource.swift`: the debug fault hooks (250-343).
- `LoginView.swift`: lines 348-804 are `SettingsView` with its tabs.
- `DisplayModeController.swift` is wrapped whole in `#if os(tvOS)` but compiled into iOS.
- The iOS-only offline retry sits in an `#if os(iOS)` block in TVModel.swift (255-288).
- Code shared with iOS says "Apple TV" (`TVModel+Recordings.swift:61, 80`).

## Goals / Non-Goals

**Goals:**
- No visible or logged behavior changes, except log lines that a moved piece prints with a
  different `#function`.
- Each phase leaves `main`-ready code that builds on all platforms and passes every test.
- After phase 3, a rule that Mac and TV share has one implementation, and a fix lands once.

**Non-Goals:**
- Rewriting algorithms while moving them. A moved function keeps its body. Improvements come
  later, in their own commits.
- Equalizing the apps' UIs, or making the Mac use `TVModel`.

## Decisions

### 1. Three phases, each committed alone, in order of risk

Phase 1 (deletions, docs) and phase 2 (pure moves) are mechanical and easy to review. Phase 3
changes call sites across apps, so it starts only after the first two are green, and each
extraction in it is a commit of its own. A `git bisect` then lands on a small step.

Rejected: one large refactoring commit. It cannot be reviewed, and a regression would be hard
to place.
Rejected: phase 3 first, for the biggest win. Moving logic is easier once the files are split
and the dead code is gone.

### 2. Splits are moves into extensions or files of the same module

A large type becomes its main file plus `Type+Part.swift` extensions, for example
`PlaybackSession+Video.swift`, `PlaybackSession+Audio.swift`, `PlaybackSession+Monitor.swift`
and `PlaybackSession+Live.swift`. Nested helper types (`LastPicture`, `PlayerError`,
`BufferHistory`, …) get their own files. Stored properties stay in the main declaration (Swift
does not allow them in extensions). `private` members used from another of the new files
become internal, and only those. Access never becomes public just for a split.

Rejected: new types that own parts of the session (`VideoPipeline` as a class). It would be
cleaner, but it changes the locking and lifetime that the session relies on, so it is a
behavior risk, not a cleanup.

### 3. Shared logic goes where both callers can reach it

- Rules without FFmpeg or UI go to FernsyCore: sync rules, debug environment parsing
  (`DebugEnv`, debug builds only), item key and label helpers, Jellyfin tick conversion.
- Playback start helpers that need the engine go to FernsyPlayer: Jellyfin start, cloud source
  with failure, archive playback.
- Logic shared by Apple TV and iOS only (StartBuilder setup, Start refresh inputs, the
  TV↔iOS helpers) moves into `TVModel` extensions, which both targets compile.

Each shared helper takes what differs as parameters or closures (for example how the IPTV
login is done in sync). It does not grow `#if os(...)` branches.

Rejected: a protocol both `AppModel` and `TVModel` adopt, with the shared logic as protocol
extensions. It ties the two models together and spreads requirements over both, for a gain the
plain functions also give.

### 4. Platform-only code lives in platform-only files

Files whose content is for one platform leave the other target through the membership
exceptions instead of `#if os(...)` around the whole file: `DisplayModeController`, and the
iOS offline retry moved into `TVModel+Offline.swift` (iOS only). Small `#if` blocks inside
otherwise shared code stay.

### 5. Finds that change behavior are written down, not fixed here

The "S1 F2" episode label and the two "next episode" rules are noted in tasks.md's follow-up
section and fixed after this change. The episode rule is specified behavior and may need a
change of its own.

## Risks / Trade-offs

- [A move changes behavior through access or initialization order] → Moves keep bodies
  unchanged; after each phase the FernsyCore and FernsyPlayer tests, `scripts/test.sh`, the
  Apple TV UI tests (`scripts/tv-uitest.sh`), the iOS UI tests (`scripts/ios-uitest.sh`) and a
  Mac dev run on the demo server run.
- [The Mac app has no UI tests] → After phases 2 and 3, a Mac dev build ("Fernsy Dev",
  `scripts/dev-run.sh` with the demo server) plays a channel, a film and a recording through
  its MCP tools and checks the settings tabs. The MCP tools answer from the same code paths.
- [Merge conflicts with work in flight] → `tvos-match-content` and the Continue Watching fix
  touch `PlaybackSession`, `PlayerEngine`, `TVModel` and the Start views. This change starts
  after both are merged into `main`.
- [Large diffs hide a mistake] → Phase 2 commits are moves only; `git diff --color-moved` shows
  them as moved, which makes a changed line stand out.

## Migration Plan

Code only, no data or settings. Each phase is merged into the change branch as its own commits.
A phase that causes a regression is reverted on its own.

## As built

- 1.4: DEVELOPMENT.md does not list every debug switch on purpose ("further debug-only switches
  … are documented where they are read"). Eight of the nine switches the survey reported as
  undocumented already had that comment in the code; only `IPTV_TESTZAP` lacked one and got it.
- 1.2: `ResumeStore.episodeKey` took an `Int`, while IPTV episode ids are strings: that is why
  it was never used. It now takes a `String`. The Mac build caught the mismatch;
  `scripts/test.sh` did not, because it runs the Mac package tests and a tvOS build that
  builds no app target ("Supported platforms for the buildables in the current scheme is
  empty"). Phase verification therefore builds the Mac app itself (`scripts/dev-run.sh`) and
  relies on the UI test scripts for tvOS and iOS.
- Phase 2: the splits were done by a script that cuts marked regions into `Type+Part.swift`
  extensions and moves stored properties back into the type; access was then opened only where
  the compiler reported a cross-file use (private → internal, `private(set)` → internal set).
  `git diff --color-moved --color-moved-ws=allow-indentation-change` shows no changed line
  besides those access modifiers and the new `runDebugHooks()` call. The private property
  `sync` had to become internal although no error named it: in another file it resolved to the
  global `sync()` function instead.
- 3.1: `ICloudSync` lives in FernsyPlayer, not FernsyCore as decision 3 planned: the synced keys
  include the recorder's padding keys (`Recorder` is in FernsyPlayer). Pitfall: the launch
  sign-in first kept the steps in a local copy and wrote it back; the model's own sign-in also
  changes them (`finish(.provider, then: .channels)` when the channels load), so the provider
  step stayed "running". `AutoSignInUITests.testProviderLoginSignsInAtLaunch` caught it. The
  helper now reads and writes the model's steps for each change.
- Phase 3 verification per step: package tests, `scripts/test.sh`, builds of all three apps,
  the UI test classes that cover the moved code, and a Mac dev run of the affected path; the
  full Apple TV and iOS suites run once at the end (3.8) instead of after every step.
- 3.6: shared by Apple TV and iOS now: `Runtime`, `DetailTarget`, the search hit, the film facts,
  position and duration, the episode rows (`LibraryDetail`), the search (channels, show hits,
  index, film and series hits) and Übersicht's inputs (`TVModel+Search.swift`), and short texts
  (`LibraryText`). Left in the views: the film and series pages' loading, playing and favourite
  toggling. They work on each view's own state; sharing them needs a shared view model, a design
  change rather than a cleanup.

- 3.7: two messages in the shared recordings code named the Apple TV or tvOS on iOS too: the
  free-space refusal and the missing-file notice. Both are per platform now (`#if os(tvOS)`); iOS
  says "this device" and "the system". iOS keeps recordings in Caches as well, so the system can
  clear them there too.
