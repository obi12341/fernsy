# Tasks

## 0. English as the source language

- [x] 0.1 `scripts/flip-source-language.py` per design K (steps 1–3): rewrite literals without interpolation and with interpolations, report keys without literals and English collisions; resolve the collisions with distinct English texts. Verify: the report lists no unresolved key; `git diff --stat` touches only Swift files with UI texts.
- [x] 0.2 Rebuild `Localizable.xcstrings`, `AppShortcuts.xcstrings` and `InfoPlist.xcstrings` with English source and German translations (design K step 4, plurals by hand), set `developmentRegion = en`, update the project context in `openspec/config.yaml` (English source, German translation). Verify: Debug, Direct and Release builds with 0 warnings; `xcstringstool` sync reports no new or stale keys; every key has a German translation.
- [x] 0.3 Language runs with the dev build against the demo server (`IPTV_SECTION=recordings`, and `IPTV_AUTOPLAY=live:101 IPTV_TESTNET=trickle:15 IPTV_TRICKLEMORE=all` for a player status card, each with `-AppleLanguages "(de)"`, `"(en)"`, `"(fr)"`): window screenshots show German, English and English. The Siri phrases are checked through the catalog comparison (every phrase the compiler extracts is a catalog key with a German translation), because the Shortcuts list needs clicks. Verify: compare the German screenshots with the previous wording; no English text in the German UI and vice versa.

## 1. Package skeleton

- [x] 1.1 Create `Packages/FernsyCore` (Package.swift per design A, `Sources/FernsyCore`, `Tests/FernsyCoreTests`, empty `Localizable.xcstrings` as resource) and link it from both app targets as a local package. Restore Xcode's `alwaysOutOfDate` reordering in `project.pbxproj` from HEAD. Verify: Debug builds of `Fernsy` and `Fernsy Direct` with 0 warnings; `git diff` of the project file shows only the package reference and the two product dependencies.
- [x] 1.2 Move `ChannelName` with `debugLog` and `AppLog` (needed by it and almost everything else) into the package, make what the app uses `public`, add `import FernsyCore` where needed. Turn `ChannelName.selfTest` and `AppLog.selfTest` into `ChannelNameTests` and `AppLogTests`, remove the functions and the `IPTV_NAMETEST`/`IPTV_LOGSELFTEST` switches. Verify: `xcodebuild test -scheme FernsyCore -destination 'platform=macOS'` passes all 20 name cases and the secrets test; make one name case fail on purpose once and see the test name it.
- [x] 1.3 `scripts/test.sh`: macOS tests plus `xcodebuild build -scheme FernsyCore -destination 'generic/platform=tvOS Simulator'`. Verify: it exits 0, and exits non-zero when a test fails.

## 2. Move the shared logic

- [x] 2.1 Move `XtreamModels`, `XtreamClient`, `EPGStore` (design B). Verify: both app targets build with 0 warnings; demo-server run (`scripts/dev-run.sh IPTV_AUTOPLAY=live:101`) loads the catalog and EPG and plays.
- [x] 2.2 Move `JellyfinModels`, `ContentHistory`, `MediaInfo`, `TrackChooser` (with `TrackChooserTests` from its self-test, `IPTV_TRACKSELFTEST` removed). Verify: builds with 0 warnings; tests pass.
- [x] 2.3 Move `RecordingPlan` (with `RecordingPlanTests`, `IPTV_PLANTEST` removed) and `GapTracker` out of `Recorder.swift`, plus `GapTrackerTests` (design E). Verify: tests pass; demo-server recording run (`IPTV_TESTRECORD=101:5:150:0:0 IPTV_TESTNET=trickle:30 IPTV_TRICKLEKBIT=100 IPTV_TRICKLEMORE=2`) still lists its gap while running.
- [x] 2.4 Strings per design D: package calls use `bundle: .module`, their keys move from `Fernsy/Localizable.xcstrings` to the package catalog with translations, plus `LocalizationTests`. Verify: `grep -rn 'String(localized:' Packages/FernsyCore/Sources | grep -v 'bundle: .module'` is empty; the app catalog has no stale keys of moved code; dev builds with `IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev/nothing` (the demo server answers HTTP 404 there; it accepts any password, so a wrong one shows nothing) log the package's error as "Server-Fehler (HTTP 404)" with `-AppleLanguages "(de)"` and "Server error (HTTP 404)" with `"(en)"`.

## 3. Slow-delivery rule as a value type

- [ ] 3.1 `DeliveryMonitor` in the package per design B; `HTTPByteSource.checkStall` uses it with `Date()`, keeping lock, timers, reconnect and the existing log lines. Verify: builds with 0 warnings; demo-server runs `IPTV_TESTNET=trickle:30` (replaced "too slow … (load balancer)"), `IPTV_TESTNET=trickle:20 IPTV_TRICKLEMORE=all` ("judging over 30 s", "60 s", then about one switch a minute) and `IPTV_TESTNET=drop:20` ("(same edge)", no slow reconnect) give the same log lines as before the change.
- [ ] 3.2 `DeliveryMonitorTests` (design E) with a fed clock. Verify: tests pass and run in under a second.

## 4. Network fixtures

- [ ] 4.1 Record Xtream fixtures once from the demo server into `Tests/Fixtures` (live, VOD and series lists, categories, account info, an EPG answer) and write `XtreamDecodingTests` and `XtreamClientTests` with a `URLProtocol` stub, including HTTP 401 and invalid JSON, and that the password is masked in log entries. Verify: tests pass with Wi-Fi off (or `networksetup` not needed: the stub never lets a request out, checked by a test that fails on any unstubbed request).
- [ ] 4.2 `JellyfinModelsTests` with fixtures recorded from the local Docker test Jellyfin (`docker start` of the test container, read-only API calls, ids and names replaced), never from the user's server. Verify: tests pass; fixtures contain no token or user id of any real server.

## 5. CI and docs

- [ ] 5.1 `.github/workflows/tests.yml` per design F (push to `main` and `change/**`, pull requests, `workflow_call`; installs the tvOS runtime when missing; runs `scripts/test.sh` and the tests on a tvOS simulator). Verify: a push of this branch runs it green on GitHub.
- [ ] 5.2 `release.yml` calls the test workflow as a job; `dmg` and `appstore` need it. Verify: a manual `appstore-test` run shows the test job first; on a throwaway branch with a failing test, `workflow_dispatch` of `release.yml` with `--ref` that branch stops before `dmg` (then delete the branch).
- [ ] 5.3 DEVELOPMENT.md: section "Tests and FernsyCore" (what belongs in the package, how to run `scripts/test.sh`, tvOS runtime, fixtures and where they come from); remove the moved self-test switches from the debug switch list. Verify: the section exists; `grep -n "IPTV_NAMETEST\|IPTV_PLANTEST\|IPTV_TRACKSELFTEST\|IPTV_LOGSELFTEST" -r Fernsy DEVELOPMENT.md` is empty.
- [ ] 5.4 `openspec validate --all --strict` exits 0; Debug, Direct and Release builds have 0 warnings; `scripts/test.sh` passes.

## Workflow follow-up

- The source-language flip is user-visible only for other system languages: its commit carries a Release-Note pair ("Fernsy zeigt sich in anderen Systemsprachen jetzt auf Englisch statt auf Deutsch." / "On Macs set to a language other than German or English, Fernsy now appears in English instead of German."). The package commits are internal.
- Remove `scripts/flip-source-language.py` before archiving (it is a one-time tool; the design keeps the method).
- Downloading the tvOS simulator runtime on the developer's Mac (several GB) only with the user's agreement; CI installs its own.
- Archive, merge into main, push and nightly only with the user's agreement.
