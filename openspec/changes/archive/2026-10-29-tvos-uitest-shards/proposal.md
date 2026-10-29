# Proposal

## Why

The Apple TV job in `tests.yml` takes about 26 minutes per push, and the whole Tests run waits for
it. In the last green run (40835517327) the time split up like this:
- setup and FFmpeg cache: about 0.3 min
- `build-for-testing`: 1.6 min
- UI tests: 24 min, about 58 tests in 25 classes, 50 app launches of 7 to 92 s each (mean about
  28 s)

No single test dominates. The time comes from driving tvOS focus with the remote on a GPU-less
runner, one launch after another. Nightlies wait for this run too, and so does every check after
a merge.

## What Changes

- **Shards (option A from the exploration).** `scripts/tv-uitest.sh` gains `--shard <i>/<n>`. It
  reads the UI test classes from `FernsyTVUITests/*.swift` and assigns each class to exactly one
  of n parts, balanced by test count, and runs only its part. `--list` prints the parts without
  running them. Without `--shard` the script runs everything, as before (local use is unchanged).
- The `apple-tv` job in `tests.yml` becomes a matrix over 3 shards. Each shard builds for testing
  and runs its part. The shards run in parallel and all three must pass. One failing shard does
  not cancel the others, so a run shows all failures.
- **Waits on a state, not on time (option E).** The tvOS UI tests have 86 fixed sleeps of
  0.5 s or more. Every one that stands for a state the app shows becomes a wait for that state,
  with a timeout:
  - focus arrived (the player "takes focus a moment after it starts")
  - a screen appeared
  - a row loaded
  - a pill was selected
  - a log line was written

  A fixed sleep is too short on a slow runner, which makes the test fail by chance, and too long
  on a fast one, which wastes time. A wait on the state is right for both. This is mainly for
  robustness. The time saved is a side effect. Sleeps whose point is real time stay:
  - the 20 s of timeshift buffer in `PlayerUITests`
  - the 6 s of backdrop movement in `LivingHeroUITests`

  Short pauses between remote presses where nothing observable changes also stay, and so does
  the settling before a screenshot.
- The script's header comment ("About 30 s when everything is built", long outdated) states the
  real duration and the shard option.

Out of scope:
- Parallel simulators on one runner (option B). The runner has few cores and no GPU, and the
  fixed debug MCP port 52325 would collide between clones.
- Running the UI tests only for tvOS-related changes (option C). 31 of the last 32 runs touched
  tvOS-related files.
- A smaller test set on pushes with the full set only at night (option D). It would publish
  nightlies from commits whose full run never passed on push.
- Speeding up the tests themselves beyond the fixed waits, such as fewer app launches per class.
- The iOS job and the `core` job.

## Capabilities

### New Capabilities

### Modified Capabilities
- `distribution`: "Apple TV app in CI" runs the UI tests split into parallel parts. Every test
  runs in exactly one part, and the run fails when any part fails.

## Impact

- `scripts/tv-uitest.sh`: the `--shard i/n` and `--list` options and class discovery.
- `.github/workflows/tests.yml`: the `apple-tv` job becomes a matrix (3 shards). Only shard 1
  saves the FFmpeg cache, and the result bundle artifact is named per shard.
- `FernsyTVUITests/*.swift`: state waits instead of sleeps (design 5), with shared helpers in `UITestSupport.swift`.
- `FernsyTV/Screens/PlayerScreen.swift`, `VODPlayerScreen.swift`, `RecordingsScreen.swift`, `RootScreen.swift`: accessibility markers for the tests (`player.surface`, the selected tab as the value of `tabs`), with no change in behaviour.
- `scripts/tv-uitest.sh`: `DEVICE_NAME` can name another simulator. The other agent also
  works on tvOS UI tests, so the edits stay small to keep merges easy.
- DEVELOPMENT.md › Apple TV: the shard option.
- Runner use: 3 macOS jobs instead of one for the Apple TV part. With `core` and `ios` that makes
  5 parallel macOS jobs, which is the free plan's concurrency limit for a public repo. A release
  run started at the same time waits in the queue. Runner minutes stay free (public repository).
- Expected wall time of the Tests run: about 10 to 12 minutes instead of about 26.
