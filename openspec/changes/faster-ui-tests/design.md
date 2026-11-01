## Context

`FernsyTVUITests` has 30 classes and 70 tests on `FernsyUITestCase` (`UITestSupport.swift`:
`launchDemo`, `wait(_:_:)`, `shot`, MCP calls). Every test launches the app, signs in to the demo
server and reaches its screen with the Siri Remote: tab focus loops (`for _ in 0..<6 where
!tab.hasFocus { press(.right); sleep(0.4) }`), then down/right until an identifier has focus. Tabs
are found by their English label. The app already understands `fernsy://open?item=…` and
`fernsy://play?item=…` (`TVModel.handle(url:)`, waiting up to a minute for the catalog), used by
the Top Shelf; the iOS app has `IPTV_TAB` and `IPTV_DETAIL` for screenshots, the Apple TV app has
neither.

## Goals / Non-Goals

**Goals:**
- Tests that only need a screen reach it without the remote.
- No fixed sleeps where a condition can be waited for; navigation helpers that fail with a
  message saying what had focus.
- A before/after measurement per test class.

**Non-Goals:**
- Changing what the tests check; tests of navigation keep navigating.
- Release builds: the switches are `#if DEBUG`.

## Decisions

### 1. `IPTV_OPEN` reuses the Top Shelf links
At launch, a debug build passes `IPTV_OPEN` to `handle(url:)` as if the system had opened the
link. The link handling already waits for sign-in and catalog and opens pages or plays, so tests
and the Top Shelf exercise the same path.
Rejected: a separate test-only navigation (a second way into the screens that users never take).

### 2. `IPTV_TAB` on the Apple TV like on iOS
`IPTV_TAB=<live|films|series|jellyfin|recordings|search|settings>` selects the tab at launch (the
`Tab` enum's case names). Combined with `IPTV_OPEN` when a page inside the tab is needed.

### 3. Helpers in `FernsyUITestCase`
- `tab(_ app, _ id)`: the tab bar button for a tab, by the English or German label (tab items take
  no accessibility identifier in SwiftUI's `Tab`; the label list is in one place).
- `focus(_ element, in app, moves:)`: presses the given directions until the element has focus,
  waiting for the focus change after each press (`pressAndWaitForFocusMove` exists) instead of a
  fixed 0.4–0.6 s; fails naming the focused element.
- `waitFor(_ element, value:, timeout:)` and `waitUntil(timeout:_:)` (the existing `wait`) for
  values such as `player.state`.
Fixed `Thread.sleep` stays only where time itself is the subject (a countdown, a 2 s debounce).

### 4. Measure from the result bundles
`xcrun xcresulttool get test-results tests` gives each test's duration; a small script
(`scripts/uitest-times.sh`) prints them per class. Baseline from a full run before the change,
the same after, both in this design's "As built".

### 5. Optional: parallel workers locally
`tv-uitest.sh`/`ios-uitest.sh` take `--parallel <n>` (`-parallel-testing-enabled YES
-parallel-testing-worker-count n`), off by default; CI keeps its three shards. Decided after the
measurement whether it is worth it (simulator clones cost memory and start time).

## Risks / Trade-offs

- [A link opens the page before the screen under it is ready, so Back behaves differently] →
  tests that check Back or focus restoration keep navigating.
- [Waiting on focus changes hides a slow app] → the helpers have timeouts; the measurement shows
  if a class got slower.

## Migration Plan

Class by class; each converted class must pass three times in a row locally (playback classes on
the host, the rest in the test VM) before the next.

## As built

- Focus queries are expensive in XCUITest (about a second each: the `hasFocus` predicate walks
  the whole tree). Waiting for each focus move (`pressAndWaitForFocusMove`, `focus(_:in:moves:)`)
  is right for a few moves where a lost press breaks the test; for long runs along one row
  (the search letter row, 30 keys) quick presses with a short pause and one check at the end
  are faster. `testFindAndPlay` went from 20 s to 49 s with per-move waits and back to 33 s.
- Tests that check navigation itself start from the tab bar (`showTab`) even when launched with
  `IPTV_TAB`: on the Search tab the launch focus is in the field, and moving up leaves the
  content.
