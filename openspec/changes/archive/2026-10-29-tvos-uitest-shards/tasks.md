# Tasks

## 1. Shards in the script

- [x] 1.1 `scripts/tv-uitest.sh`: find the classes (pattern from design 2), assign them greedily by test count, and add `--shard i/n` (adds one `-only-testing` per class) and `--list` (prints the parts and exits). Fail on an empty part or when no class is found. Without `--shard`, behaviour is unchanged.
- [x] 1.2 Update the header comment: the real duration, `--shard` and `--list`.
- [x] 1.3 Check locally without the simulator: `scripts/tv-uitest.sh --list` for 1, 2 and 3 parts. Every class appears exactly once, and the class count matches `grep` over `FernsyTVUITests/`.

## 2. Workflow

- [x] 2.1 `tests.yml` › `apple-tv`: matrix `shard: [1, 2, 3]`, `fail-fast: false`, name "Apple TV app and UI test (<i>/3)", run `scripts/tv-uitest.sh --shard <i>/3`. Only shard 1 saves the FFmpeg cache. The artifact is named `apple-tv-uitest-results-<i>`.
- [x] 2.2 Update the header comment of `tests.yml`. Run actionlint (via nix, ignoring the custom `xcode-27` label).

## 3. Wait for a state, not for time

- [x] 3.1 `UITestSupport.swift`: add the helpers `waitForFocus`, `waitForPlayerFocus`, `waitForLog`, `pressAndWaitForFocusMove` and `typeOnKeyboard` (design 5).
- [x] 3.2 Sort all sleeps of 0.5 s or more in `FernsyTVUITests/` into the four kinds (design 5). Replace every "stands for a state" sleep with a state wait. Required cases: the player focus in LiveTV and Recordings, the 18 s in GuideFocus, the tab screen in `UITestSupport`, the selection in `UITestSupport`, and the 4 to 5 s in LivingHero, LiveTV, Search and StartScrolling. Each wait has a timeout at least as long as the old sleep.
- [x] 3.3 Comment the sleeps that stay ("real time" or "no observable state"), so later readers do not "fix" them.
- [x] 3.4 Build the UI tests without running them (`xcodebuild build-for-testing`, scheme "Fernsy TV", own derived data path) so the edits compile, then run the changed test classes on a separate simulator (`DEVICE_NAME="Claude Apple TV"`, demo server; local runs allowed by the user on 2026-10-29).

## 4. Docs and verification

- [x] 4.1 DEVELOPMENT.md › Apple TV: `--shard` and `--list`, and that CI runs 3 shards.
- [x] 4.2 With the user's consent, push the branch and open a pull request. Its Tests run shows 3 Apple TV shards in parallel, all green against the demo server (`IPTV_SERVER` demo, as in `UITestSupport`). Note the wall time of the run and of each shard. Done: PR #2, run 40868725254 all green; run 13.3 min (was about 26), shards 12.8, 13.2 and 13.1 min, core 2.5 min, iOS 1.9 min.
- [x] 4.3 `openspec validate --all --strict`.
