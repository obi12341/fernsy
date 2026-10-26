# Proposal

## Why

Fernsy has no automated tests. The Xcode project has two app targets and no test target.
Logic is checked by hand: debug runs against the demo server, and five self-tests that print
"pass"/"FAIL" to stderr when an environment switch is set (`IPTV_NAMETEST`, `IPTV_PLANTEST`,
`IPTV_TRACKSELFTEST`, `IPTV_LOGSELFTEST`, `IPTV_LOGOTONETEST`). Nothing runs them in CI, so a
regression in, say, channel-name parsing or the recording plan ships unnoticed. The most
fragile new logic (the slow-delivery rule and recording gaps of
`slow-live-stream-reconnect`) can only be checked with minute-long demo runs.

The UI's source language is German, with English as the only translation. Further languages
are planned. Translators and translation tools work from English, a public repository is
easier to contribute to with English keys, and a language Fernsy does not have falls back to
the development language: today that is German, so a French Mac shows German, although the
`localization` spec promises English. Moving the shared code is the moment to flip this,
because its strings move into a new catalog anyway.

An Apple TV version is being considered. Most of Fernsy's logic is already free of AppKit
(the Xtream and Jellyfin clients and models, channel names, the recording plan, the log), but
it lives in the app target, so another platform could not use it. Pulling it into a package
with tests is worth doing for the Mac app alone, and it is the first step if tvOS follows.

## What Changes

- English becomes the UI's source language everywhere: every localized literal in the code is
  English, the string catalogs (`Localizable`, `AppShortcuts`, `InfoPlist`) have English as
  source and German as a translation, and the project's development region is English. The
  German texts stay word for word as they are. A language Fernsy does not have shows English.
- A local Swift package `FernsyCore` (in `Packages/FernsyCore`) holds the platform-independent
  logic: Xtream models, client and EPG store, channel names, Jellyfin models, the recording
  plan, the recording gap tracker, content history, track choice, the app log, and the
  slow-delivery rule as a small value type (`DeliveryMonitor`) that `HTTPByteSource` uses.
- The package builds for macOS and tvOS. Both app targets (`Fernsy`, `Fernsy Direct`) link it.
- Tests with Swift Testing in the package: the existing self-test cases become tests, plus new
  tests for the slow-delivery rule, recording gaps, Xtream and Jellyfin decoding, and the
  Xtream client against a stubbed network.
- The env self-tests that move (`IPTV_NAMETEST`, `IPTV_PLANTEST`, `IPTV_TRACKSELFTEST`,
  `IPTV_LOGSELFTEST`) are removed; `IPTV_LOGOTONETEST` stays with the view it tests.
- CI runs the tests on macOS and builds the package for the tvOS simulator, on every push to
  `main` and `change/*` branches. A nightly or release is only built from a commit whose tests
  pass.
- DEVELOPMENT.md explains how to run the tests and what belongs in the package.
- No user-visible behavior changes beyond the fallback language: German and English users see
  the same texts as before; users of other system languages see English instead of German.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `localization`: English is the source language and the fallback; German is a translation,
  and further languages need translations only.
- `distribution`: a new requirement that the shared logic lives in a package with automated
  tests, that CI runs them, and that a nightly or release is not built from a failing commit.

## Out of Scope

- An Apple TV app, tvOS UI, or a tvOS build of FFmpeg.
- Moving FFmpeg-bound code into the package (`PlaybackSession`, `TimeshiftWriter`,
  `TSAudioTap`, renderers, `HTTPByteSource` itself). It needs FFmpeg as an XCFramework for
  every platform, which belongs to the tvOS work.
- Moving `JellyfinClient`, `JellyfinStore`, `JellyfinPlayback`, `Recorder`, `Keychain`, the
  MCP server and all views.
- UI tests (XCUITest) and tests of the playback pipeline. Playback keeps being verified with
  debug runs against the demo server.
- Code coverage targets.
- Adding a third language, and changing any German or English wording.
- App Store metadata (primary language and texts in App Store Connect stay as they are).

## Impact

- All Swift files with localized literals (German literals become English), the three string
  catalogs (rebuilt with English source), `developmentRegion` in `project.pbxproj`, and the
  project context in `openspec/config.yaml` (source language).
- New `Packages/FernsyCore/` (Package.swift, Sources, Tests, its own string catalog).
- `Fernsy.xcodeproj/project.pbxproj`: local package reference, product dependency in both
  targets.
- Moved files from `Fernsy/Xtream`, `Fernsy/Jellyfin/JellyfinModels.swift`,
  `Fernsy/Recording/RecordingPlan.swift`, `Fernsy/Player/ContentHistory.swift`,
  `Fernsy/Player/TrackChooser.swift`, `Fernsy/Player/MediaInfo.swift`, `Fernsy/App/AppLog.swift`;
  `GapTracker` out of `Recorder.swift`; the slow-delivery rule out of `HTTPByteSource.swift`.
  Types used by the app become `public`; app files add `import FernsyCore`.
- Strings of moved code move to the package's catalog (German source, English translation).
- `.github/workflows/`: a test workflow, and the release workflow waits for it.
- DEVELOPMENT.md: section on tests and the package.
