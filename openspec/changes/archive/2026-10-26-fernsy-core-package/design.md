# Design

## Context

- The project (`Fernsy.xcodeproj`) has two application targets, `Fernsy` (App Store) and
  `Fernsy Direct` (DMG with Sparkle), both on file-system-synchronized groups over `Fernsy/`,
  Swift language mode 5, macOS 27, and one remote package (Sparkle). There is no test target.
- About 21,000 lines of Swift. AppKit is used in 15 files, all in `App`, `Views`, `MCP`,
  `Player` (window and PiP code), `Recording/Recorder.swift` and `Support`. None of
  `Fernsy/Xtream/*`, `Jellyfin/JellyfinModels.swift`, `Recording/RecordingPlan.swift`,
  `Player/ContentHistory.swift`, `Player/TrackChooser.swift`, `Player/MediaInfo.swift` or
  `App/AppLog.swift` uses AppKit, FFmpeg or app-level types beyond `AppLog` and `debugLog`.
- `debugLog` is defined at the end of `PlayerEngine.swift` (DEBUG only); `AppLog` is used
  almost everywhere.
- Five self-tests run from `AppModel.debugBootstrap` on an env switch and print
  "pass"/"FAIL": `ChannelName.selfTest` (20 cases), `RecordingPlan.selfTest` (the spec's
  examples), `TrackChooser.selfTest`, `AppLog.selfTest` (secrets never survive) and
  `LogoTile.selfTest` (a SwiftUI view).
- Two pieces of logic from `slow-live-stream-reconnect` were only verified with demo runs of
  several minutes: `GapTracker` (in `Recorder.swift`, already a value type taking the wall
  time as a parameter) and the slow-delivery rule (inline in `HTTPByteSource.checkStall`,
  reading `Date()` and the instance's state under `cond`).
- CI: `.github/workflows/release.yml` (jobs `prepare`, `dmg` and `appstore` on the runner
  label `xcode-27`, appcast on Ubuntu) builds nightlies on a schedule and releases on tags.
  Nothing runs on an ordinary push except Pages.
- Toolchain: Xcode 27.1, Swift 6.4. No tvOS simulator runtime is installed on the
  developer's Mac yet.

- Localization: `developmentRegion = de`; `Fernsy/Localizable.xcstrings` (source `de`, 528
  keys, 102 with placeholders, 6 with plural variations, all with English),
  `AppShortcuts.xcstrings` (12 Siri phrases), `InfoPlist.xcstrings` (one usage description);
  `de.lproj`/`en.lproj` hold the credits. Keys are the German literals in the code
  (`Text("…")`, `Button("…")`, `.help("…")`, `String(localized: "…")`, App Intents phrases).

## Goals / Non-Goals

**Goals:**
- Tests that run in seconds without network or account, locally and in CI.
- The shared logic compiles for tvOS from now on, so it stays portable while the Mac app
  evolves.
- No behavior change in the app beyond the fallback language, and no new warnings.
- Adding a language later means adding translations to the catalogs, nothing else.

**Non-Goals:**
- A tvOS app, FFmpeg for tvOS, or moving FFmpeg-bound code (see proposal, Out of Scope).
- Restructuring the moved code beyond what testing needs.

## Decisions

### K. English as the source language (done first)

The flip comes before the package work, so the package's catalog starts in English and the
move does not touch every string twice.

Method: a script (kept in `scripts/flip-source-language.py` until the change is archived, then
removed) rewrites the code and builds the catalogs:
1. For each key of the three catalogs, find the Swift string literals that produce it. A
   literal without interpolation matches the key exactly. A literal with interpolations matches
   when its text segments equal the key's text between placeholders; its interpolations are
   then reordered as the English value's positional placeholders (`%1$@`, `%2$lld`) require.
2. Replace each literal with the English value, writing interpolations back in.
3. Report every key that has no literal (built dynamically, or only in a catalog) and every
   pair of German keys with the same English value. Collisions with different German texts get
   a distinct English text by hand, so no German wording is lost.
4. After a build, `xcstringstool sync` against the build's `.stringsdata` gives the new keys
   exactly as the compiler extracts them; the new catalog takes each key's German translation
   from the script's mapping (old German key, argument order) and the English entry becomes
   the source. Plural variations are rebuilt by hand for the six plural keys.
5. `developmentRegion` becomes `en` (`knownRegions` keep `de`, `en`, `Base`).

Checks: no German literal left in the code (a list of German-only characters and words over
literals, reviewed by hand), every catalog key has a German translation, no stale keys, and
dev builds in German, English and French (`-AppleLanguages "(fr)"`) show German, English and
English. A package test reads all catalogs and fails on any key without a German translation,
so a new string cannot ship untranslated.

Rejected: keeping German as source and only adding languages. It works technically, but the
fallback for languages Fernsy lacks would stay German, and every future translation would be
made from German.
Rejected: semantic keys (`player.card.slow.title`) instead of English text as keys. They
survive wording changes, but SwiftUI's literal-based `Text("…")` extraction would no longer
work, every view would need explicit lookups, and the code becomes harder to read.

### A. One local package, one library product

`Packages/FernsyCore/Package.swift` (tools version 6.x, `swiftLanguageModes: [.v5]` like the
app, platforms macOS 27 and tvOS 27, `defaultLocalization: "en"`), one library product
`FernsyCore`, one test target `FernsyCoreTests`. The Xcode project references it as a local
package (`XCLocalSwiftPackageReference`) and both app targets link the product, next to
Sparkle.

Rejected: a unit-test target inside the Xcode project with `@testable import Fernsy`. It is
the smallest step to tests, but the test bundle would load the whole app with FFmpeg, run
only on macOS, and give tvOS nothing to build on.
Rejected: several packages (FernsyXtream, FernsyJellyfin, …). One module is enough until a
second app needs a different subset; splitting later is mechanical.

### B. What moves, what stays

Moves (file by file, contents unchanged except access control and the points below):
`Xtream/XtreamModels.swift`, `XtreamClient.swift`, `ChannelName.swift`, `EPGStore.swift`;
`Jellyfin/JellyfinModels.swift`; `Recording/RecordingPlan.swift`; `GapTracker` from
`Recorder.swift` into its own file; `Player/ContentHistory.swift`, `TrackChooser.swift`,
`MediaInfo.swift`; `App/AppLog.swift` together with `debugLog`.

New in the package: `DeliveryMonitor`, the slow-delivery rule of `HTTPByteSource` as a value
type. It holds the content samples, the escalation level and the per-connection figures, and
its `sample(now:content:)` returns what the rule decides (keep, replace with this reason,
slow for the card) plus the figures for the log line. `HTTPByteSource` keeps its lock, its
timers and the reconnect itself, and calls the monitor inside `checkStall` with `Date()`.
The rule's behavior and log lines stay exactly as they are; the tests feed a clock.

Stays: everything FFmpeg-bound, `HTTPByteSource` (it calls FFmpeg error codes), `Recorder`,
`JellyfinClient/Store/Playback`, `Keychain`, MCP, views. `JellyfinClient` reads
`UserDefaults` and would need injection; it can follow when tvOS needs it.

Rejected: moving `HTTPByteSource` with an abstraction over the FFmpeg error codes. It would
touch the reconnect code far more than this change needs.

### C. Access control

Types and members the app uses become `public`; the rest stays internal. `package` access
does not help: an Xcode app target and a local package are different packages. Tests use
`@testable import FernsyCore` for internals.

### D. Strings of moved code

Moved code that calls `String(localized:)` resolves against the main bundle and would find
nothing once its keys live elsewhere. Every such call in the package passes
`bundle: .module`, and the package gets its own `Localizable.xcstrings` (English source,
German translations, `defaultLocalization: "en"`) with exactly the keys of the moved code,
taken out of the app's catalog with their translations. A test asks the package bundle for one string in English, so a
missing catalog fails in CI rather than showing German keys in the English app.

Rejected: keeping the strings in the app's catalog and passing `Bundle.main` in. It saves the
move but hides a dependency on the app that tvOS would have to repeat.

### E. Tests

Swift Testing (`@Test`, parameterized arguments fit the existing case tables). Suites:
- `ChannelNameTests`, `RecordingPlanTests`, `TrackChooserTests`, `AppLogTests`: the self-test
  cases one to one; the env switches and `selfTest()` functions go.
- `GapTrackerTests`: steady delivery, a 25 s hole, bursts with 2–4 s pauses (saw tooth),
  hiccups under 10 s, a gap still growing when the recording ends.
- `DeliveryMonitorTests`: the demo-server figures (11–14 s per window) stay ok; a fifth of
  real time replaces within 20 s; 6 s bursts are kept; a repeat within 2 minutes doubles the
  window to 30 s and 60 s; 5 quiet minutes return to 15 s; the per-connection figures.
- `XtreamDecodingTests`, `JellyfinModelsTests`: JSON fixtures in `Tests/Fixtures`. Xtream
  fixtures are recorded once from the demo server (`player_api.php` actions, an EPG answer);
  Jellyfin fixtures are recorded from the local Docker test server, with ids and names
  replaced, never from the user's server.
- `XtreamClientTests`: a `URLProtocol` stub answers with the fixtures; checks URLs, decoding
  and errors (HTTP 401, invalid JSON), and that the password never appears in a log entry.
- `LocalizationTests`: one key per language from the package bundle, and every key of every
  catalog (app and package) has a German translation.

Rejected: XCTest. It works on both platforms too, but Swift Testing's parameterized tests map
the existing tables directly and are the toolchain's default.

### F. Running the tests

Locally: `xcodebuild test -scheme FernsyCore -destination 'platform=macOS'` in
`Packages/FernsyCore` (Xcode compiles the string catalog; `swift test` may not), and
`xcodebuild build -scheme FernsyCore -destination 'generic/platform=tvOS Simulator'`.
`scripts/test.sh` runs both. Running the tests on a tvOS simulator is optional locally (it
needs the tvOS runtime, several GB) and done in CI.

CI: a new workflow `.github/workflows/tests.yml` on push to `main` and `change/**`, on pull
requests, and as `workflow_call`. It runs `scripts/test.sh` plus the tests on a tvOS simulator
on the `xcode-27` runner. `release.yml` calls it as a job, and `dmg` and `appstore` need it, so
a scheduled nightly with failing tests publishes nothing and the previous nightly stays.

Rejected: checking the test workflow's status of the commit from `release.yml`. Scheduled and
manual runs would depend on a push run having finished; calling the workflow is
self-contained.

### G. Order of work

The source-language flip first (decision K), as its own commit. Then the package skeleton and project link first, with one moved file (`ChannelName`) and its tests,
so the build setup is proven before the bulk move. Then file groups, each followed by a full
build of both targets. `DeliveryMonitor` last, because it changes `HTTPByteSource`; it is
verified with the same demo runs as in `slow-live-stream-reconnect`.

## Risks / Trade-offs

- [The literal rewrite changes a string that is not a UI text but equals a key, e.g. a
  comparison with a localized error] → the script only touches literals that produce catalog
  keys, and comparisons against `localizedDescription` keep working because both sides change
  together; the full build plus the language runs catch the rest.
- [Two German texts share one English text] → reported by the script and split by hand
  (decision K), so the German UI keeps every wording.
- [Siri phrases in German stop matching] → the phrases stay as German translations of English
  source phrases; the App Shortcuts catalog keeps both languages.

- [The `public` keyword spreads through many declarations] → it is mechanical and limited to
  what the app uses; the compiler lists every missing one.
- [A `String(localized:)` without `bundle: .module` slips through] → a task greps the package
  for calls without it, and the localization test covers the catalog itself.
- [Xcode rewrites `project.pbxproj` (the known `alwaysOutOfDate` reordering)] → restore from
  HEAD and reapply only the package reference, as before.
- [The `xcode-27` runner has no tvOS simulator runtime] → the workflow installs it once with
  `xcodebuild -downloadPlatform tvOS` when `simctl` lists none; the first run takes longer.
- [Extracting the slow-delivery rule changes its behavior by accident] → its log lines stay
  identical, and the demo runs of `slow-live-stream-reconnect` (`IPTV_TESTNET=trickle:30`,
  `IPTV_TRICKLEMORE=all`, `IPTV_TESTNET=drop:20`) are repeated.
- [Tests on the release runner slow the nightly] → the suites run in seconds; the tvOS
  simulator boot adds about a minute.
