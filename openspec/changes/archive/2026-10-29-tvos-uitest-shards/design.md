# Design

## Context

- `tests.yml` › `apple-tv` calls `scripts/tv-uitest.sh`. The script runs `build-for-testing`, then
  `test-without-building` with every class of `FernsyTVUITests`. The 2-minute per-test limit and
  the printing of failure messages from the result bundle stay as they are.
- The runner is the hosted `xcode-27-arm64` image: few cores, no GPU. The repository is public, so
  macOS runner minutes are free. The free plan runs at most 5 macOS jobs at once.
- The test classes subclass `FernsyUITestCase` (some subclass `XCTestCase` directly). Some files
  hold two classes (`GuideUITests.swift`: `GuideUITests` and `AllCategoriesUITests`). Each test
  launches the app on its own, so classes are independent.
- The last green run had 50 app launches between 7 and 92 s each, 24 min in total.
- Last night the other agent asked not to run tvOS UI tests locally while it used the one tvOS
  simulator, Jellyfin container and MCP port. On 2026-10-29 the user allowed local runs on a
  separate simulator ("Claude Apple TV", demo server, no Jellyfin). The pull request's CI run
  checks the shards.

## Goals / Non-Goals

**Goals:**
- The Tests run finishes in about 10 to 12 minutes instead of about 26.
- A new UI test class is picked up without editing the workflow.
- Local use of `tv-uitest.sh` stays as it is.

**Non-Goals:**
- Faster individual tests beyond replacing waits that stand for a state.
- Changes to the iOS or `core` jobs, or to `release.yml`.

## Decisions

### 1. Split by test class across runners (matrix), not across simulators on one runner
`tv-uitest.sh --shard i/n` passes one `-only-testing:FernsyTVUITests/<Class>` per class of its
part. Each shard is a separate job on its own runner with its own simulator. Port 52325, the
simulator and the demo account do not collide, because the demo server has no stream limit.

- Rejected: `-parallel-testing-enabled` on one runner. Clones on few GPU-less cores are hardly
  faster, and all instances would bind the debug MCP port 52325.
- Rejected: split by test method. Classes share `setUp` and helpers, and per-class splitting is
  already fine-grained enough for 25 classes on 3 shards.

### 2. Classes found from the sources, balanced by test count
The script finds the classes with a pattern over `FernsyTVUITests/*.swift`:
`class <Name>: FernsyUITestCase|XCTestCase`, leaving out the base class `FernsyUITestCase`. It
counts `func test` per class. It assigns classes greedily (most tests first, ties by name) to the
part with the fewest tests so far. The result is deterministic, so every shard computes the same
split on its own and no class is run twice or left out. `--list` prints the parts, which serves
as a local check (it does not run tests). The script fails when a part comes out empty or no
class is found, so a changed class pattern cannot pass by testing nothing.

- Rejected: a hand-kept list of classes per shard in the workflow. A new class would silently not
  run.
- Rejected: balancing by recorded durations from earlier runs. It needs a file that has to be kept
  current. Test count is a rough but maintenance-free weight. If the shards turn out very uneven,
  durations can come later.

### 3. Three shards
With `core` and `ios` that makes 5 parallel macOS jobs, the free plan's limit. Expected per
shard: about 1 min setup, 1.6 min build and about 8 min of tests, so about 11 min. More shards
would queue behind the limit, and each adds its own setup and build.

### 4. The matrix job
- Job id `apple-tv` with `strategy.matrix.shard: [1, 2, 3]` and `fail-fast: false`. A failing
  shard does not cancel the others, and the run shows every failure.
- Display name "Apple TV app and UI test (<i>/3)".
- FFmpeg: all shards restore the shared cache. On a miss each shard builds FFmpeg, but only
  shard 1 saves it (two saves of one key race, same reasoning as `ci-job-names`).
- Result bundle artifact: `apple-tv-uitest-results-<i>`.
- `release.yml` is unaffected: it reads the conclusion of the whole Tests run, and in the
  reusable call every matrix job must pass.

### 5. Wait for a state, not for time (option E)
The tests have 86 `Thread.sleep`s of 0.5 s or more. Each is sorted into one of four kinds:

| Kind | Example | Becomes |
|---|---|---|
| Stands for a state | "the player takes focus a moment after it starts" (LiveTV, Recordings), the 18 s in GuideFocus (row loads), "the tab's screen follows the focus", selection settled, details loaded | a wait for that state (`hasFocus`, element exists or value, row not `loading`, app log line), with a timeout of at least the old sleep's length and generous for slow runners |
| Real time is the point | 20 s of buffer (Player), 6 s of backdrop movement (LivingHero) | stays, with a comment |
| Pacing between remote presses | 0.15 to 0.6 s inside press loops | stays; where a loop waits for focus to move, a helper that presses and waits for the focus change replaces it |
| Settling before a screenshot | `shot()` waits 1 s for animations | stays (no observable end; screenshots are evidence, not assertions) |

The shared helpers go into `UITestSupport.swift`:
- `waitForFocus(_:timeout:)`
- `waitForPlayerFocus(_:)`
- `waitForLog(_:timeout:)`, built on the existing `appLog`
- `pressAndWaitForFocusMove(_:_:timeout:)`: presses and waits until the focused element changes
- `typeOnKeyboard(_:_:)`: waits until the text field has focus again after the keyboard

Tests use these helpers instead of a sleep for each case. Two private copies of `waitForFocus` in
`TabsUITests` and `SignInUITests` give way to the shared one.

Two states had nothing a test could read, so the app gains two accessibility markers. Neither
changes behaviour:
- The three tvOS players (live, film, recording) mark their focusable surface
  `player.surface`, with the value `focused` once their `@FocusState` holds. tvOS does not report
  the focus of that container to XCUITest (`hasFocus` stays false, as a local run showed), so
  `waitForPlayerFocus` reads the value.
- The tab view (`tabs`) reports the selected tab as its value (`start`, `live`, `films`, ...),
  so `showTab` waits for the selection instead of 1 s. `isSelected` on the tab bar button does
  not work: tvOS does not report it, as a local run showed.

The main reason is robustness. A fixed sleep is too short on a slow runner (a flaky failure,
like the comments about "slow CI runners" record) and too long on a fast one. The time saved is a
side effect.

- Rejected: replacing every sleep, including press pacing and screenshot settling. There is no
  state to wait for, and touching about 140 call sites in files the other agent is working on
  invites merge conflicts with no gain.
- Rejected: only the sleeps of 4 s or more (the first draft). It leaves the 1 to 2 s "focus
  arrives" sleeps, which are the ones that break on slow runners.

## Risks / Trade-offs

- **Uneven shards.** Test count does not match duration: the slowest launch takes 92 s, the
  fastest 7 s. One shard may take a few minutes longer than the others. This is accepted, and
  recorded durations are the fallback (decision 2).
- **Queueing.** A release run during a Tests run waits for a free macOS slot. This is rare and
  costs minutes, not correctness.
- **Merge conflicts with the other agent's UI test work.** The edits stay at the sleep lines
  and the helpers. Before the merge, rebase onto its latest UI test commits.
- **A wait that never ends.** Every wait has a timeout and fails with the element tree, as the
  existing `wait(...)` assertions do.
- **Verification.** The state waits are checked locally on a separate simulator. The shards
  can only be checked on a pull request's Tests run before the merge.
