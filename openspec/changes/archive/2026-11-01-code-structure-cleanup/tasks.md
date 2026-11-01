# Tasks

The change starts from `main` after `tvos-match-content` and the Continue Watching fix are
merged (design: Risks). Each group ends with its own verification and commit.

Verification for each phase:
- **(A)** `swift test` in `Packages/FernsyCore` and `Packages/FernsyPlayer`, plus `scripts/test.sh`.
- **(B)** `scripts/tv-uitest.sh` on "Claude Apple TV" and `scripts/ios-uitest.sh` on "iPad Air
  11-inch (M4)". Both run against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
  `IPTV_USER=demo`, `IPTV_PASS=demo`, which the test classes set).
- **(C)** A Mac dev run, `scripts/dev-run.sh` with the same `IPTV_SERVER`/`IPTV_USER`/`IPTV_PASS`
  and `IPTV_MCP=1`. Through the MCP tools it plays channel 101, film `movie:500` and a recording
  made with `IPTV_TESTRECORD=101:0:20:0:0`, and the Settings window shows every tab.

## 1. Dead code and leftovers

- [x] 1.1 Remove `JFKind.itemType`, `CloudClient.devSetAccount`, and move the stray doc comment at `AppModel.swift:1100` to `play(jellyfin:)`
- [x] 1.2 Replace hand-built `"movie.\(…)"` and `"episode.\(…)"` keys with `ResumeStore.movieKey`/`episodeKey` everywhere (Mac, MCP, Apple TV, iOS)
- [x] 1.3 Remove unused catalog keys:
  - Mac: "New Movies", "New Series".
  - Apple TV: "Loading …", "Server address", the old one-account note.
  - Apple TV: the shadowed "Coming Up" and "Movies · %@".
  - Search all catalogs once more for keys without a literal in their target.
- [x] 1.4 Debug switches the survey found missing from DEVELOPMENT.md: DEVELOPMENT.md says further switches are documented where they are read, and eight of the nine have that comment; `IPTV_TESTZAP` got one (design 4.1 note)
- [x] 1.5 Verify (A), (B) and (C); commit phase 1

## 2. Split large files (moves only)

- [x] 2.1 `PlaybackSession.swift`:
  - Move `SourceBox` and the I/O trampolines to `ByteSource.swift`, made internal.
  - Add `PlaybackSession+Live.swift` (admission and rescue), `+Video.swift`, `+Audio.swift`
    (with `AudioLevelMeter`), `+Monitor.swift`, `+Subtitles.swift` (bitmap) and
    `+DebugFaults.swift`.
  - Give `LastPicture` and `PlayerError` their own files.
- [x] 2.2 `PlayerEngine.swift`: `PlaybackProgress`, `BufferHistory` and `ExternalPlayback` into their own files; the debug stall test into an extension. `HTTPByteSource.swift`: the `debug*` fault hooks into `HTTPByteSource+Debug.swift`
- [x] 2.3 Mac `PlayerScreen.swift`:
  - Give `PlayerControls`, `ChannelOSD`, the stats overlays (`AudioStatusBadge`,
    `StatsOverlay`, `BufferChart`), `NextEpisodeOverlay` and `BitmapSubtitleView` their own
    files.
  - Move the debug hooks from `onAppear` into a `PlayerScreen+Debug.swift` modifier.
- [x] 2.4 `AppModel.swift`: `debugBootstrap`, `PlayItem`, the catalog cache and refresh, visibility and favorites, series track memory and sync into `AppModel+*.swift` extensions or files
- [x] 2.5 `LoginView.swift` → `LoginView.swift` and `SettingsView.swift` (with its tabs); `MCPTools.swift`: `PlayerWindow` into `PlayerWindow.swift`
- [x] 2.6 Platform-only files leave the other target through the membership exceptions:
  - `DisplayModeController.swift` becomes tvOS-only, without its whole-file `#if`.
  - The iOS offline retry (TVModel.swift 255-288) moves to an iOS-only `TVModel+Offline.swift`.
- [x] 2.7 Verify (A), (B) and (C), and check `git diff --color-moved` for changed lines inside moved blocks; commit phase 2

## 3. One copy of shared logic

- [x] 3.1 iCloud sync rules (`syncAllowed`, `syncedKeys`, `makeLogins`, sign-in from iCloud, arrival handling) into FernsyCore. The differing IPTV sign-in and visibility pull are passed in by the Mac and the TV model
- [x] 3.2 `DebugEnv` in FernsyCore (debug builds only):
  - Credentials, `skipKeychain` and `IPTV_TESTRESUME`, used by Mac and TV.
  - One `IPTV_TESTHIDE` parser that keeps both syntaxes as they are documented.
  - The library-enlarging loop once in TVModel.
- [x] 3.3 Item helpers in FernsyCore:
  - Resume key and log/subtitle text for films, episodes, archive and cloud items, used by
    `PlayItem` (Mac) and `VODItem` (TV).
  - The archive subtitle format, the Jellyfin tick conversion and `episodeIndex`.
- [x] 3.4 Playback start helpers in FernsyPlayer (Jellyfin start, cloud source with failure report, archive playback), used by the Mac `PlayerScreen` and `TVModel+Library`. The Mac's start moves out of the view into the model
- [x] 3.5 StartBuilder setup and the Start refresh inputs (resume, live, catalog) once: shared builder setup in FernsyCore for Mac and TV, and the inputs in `TVModel` for Apple TV and iOS. iOS then also follows recordings, as the TV does
- [x] 3.6 The non-UI helpers iOS copied from the TV screens become shared `TVModel` or `LibraryEntry` functions, used by both: detail facts, position and duration texts, entries, Jellyfin search, channel list
- [x] 3.7 Platform-neutral wording for messages in code shared with iOS ("Not enough free space on the Apple TV" → per-platform text); German strings updated
- [x] 3.8 Verify (A), (B) and (C) after each of 3.1–3.7 (one commit each); a final full run of all three
  - Final run: package tests (167 + 17), `scripts/test.sh`, all three app builds and the Mac run
    passed. The full Apple TV run had no failure after 45 of 68 tests when the user had it
    merged ahead of the iPad run, since CI runs every test again before a nightly or release.

## 4. Wrap-up

- [x] 4.1 Note in design.md what was moved or merged differently from the plan, with the reason
- [x] 4.2 `openspec validate --all --strict` passes

## Workflow follow-up

- Fix afterwards, outside this change (they change what users see):
  - The episode label "S1 F2" is hard-coded and not localized (StartBuilder.swift:195/272,
    TVModel+Library:43/45, DetailScreens:366/373, FernsyiOS/LibraryViews:624/631). The Mac
    otherwise shows "S1 E2".
  - The "next episode" rule differs: the Mac (SeriesViews.swift:121-123) takes the first
    started, else the first unwatched episode; Apple TV (TVModel+Library.swift:228-233) takes
    the first started, else the one after the last watched. Check the specs and decide which
    one is right.
- Archive on `change/code-structure-cleanup`, merge into `main` and push with the user's
  consent. Release-note trailers only on 3.7 (iOS no longer names the Apple TV in two
  recording notices); the rest changes nothing users notice.
