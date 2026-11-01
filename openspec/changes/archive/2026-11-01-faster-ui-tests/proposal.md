# Proposal

## Why

The UI tests are slow and fail now and then on timing. The Apple TV suite (70 tests) takes three
CI shards of about 13 minutes each and runs about 20 minutes locally; recent failures were
timing or navigation, not bugs (`AutoSignInUITests` caught a step already done, the series tests
looked for the tab by its English label). The time goes into getting somewhere rather than
checking: 88 app launches, 251 remote presses (mostly "press, sleep, check focus" loops) and 144
fixed `Thread.sleep` calls that always run out. The Apple TV app has no way to start on a given
screen, so every test navigates there by remote.

## What Changes

- **Start where the test needs to be** (Apple TV, debug builds only): `IPTV_OPEN=<fernsy:// link>`
  hands a Top Shelf link to the app at launch (film, episode, series, Jellyfin item pages and
  playback, already handled by `TVModel.handle(url:)`), and `IPTV_TAB=<tab>` opens a tab, as the
  iOS app already can. Tests that only need to reach a screen use them instead of remote
  navigation.
- **Wait for conditions, not for time**: shared helpers in `UITestSupport` — find a tab by
  identifier, focus an element (navigate until it has focus, with a clear failure message),
  wait for a value — replace fixed sleeps and hand-written focus loops. Tabs get accessibility
  identifiers that do not depend on the language.
- **Measured**: per-test durations from the result bundles before and after, written into
  design.md, so the gain is known per class.
- Optional, after the above: parallel workers in the local test scripts (`-parallel-testing-
  worker-count`), and a "smoke" test plan for quick runs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None (debug switches and tests only; `skip_specs`).

## Impact

- Apple TV debug code: launch handling for `IPTV_OPEN` and `IPTV_TAB` (`#if DEBUG`), tab
  identifiers in `RootScreen`.
- `FernsyTVUITests` (support file and most test classes), `FernsyiOSUITests` where the same
  helpers apply, `scripts/tv-uitest.sh`/`ios-uitest.sh` for the optional parallel workers.
- DEVELOPMENT.md: the new switches and how to write a UI test with the helpers.

## Out of scope

- Another test framework (XCUITest is the only one that drives tvOS), snapshot tests, local
  fixture servers instead of the demo server: considered in exploration, not needed for the
  failures seen so far.
- Tests that check navigation itself (focus moves, row-by-row, Back) keep using the remote;
  that is what they test.
- Playback tests keep real playback on the demo server.
