# Design

## Context

Currently `tests.yml` has two jobs on the `xcode-27` runner label (GitHub-hosted, no own runners):
- `core`: about 2 minutes. FernsyCore tests on macOS and on a tvOS simulator.
- `apple-tv`: about 26 minutes. Restores or builds FFmpeg (all slices, one cache keyed by
  `scripts/build-ffmpeg.sh`), builds the iPhone and iPad app for the iOS simulator, then builds
  the Apple TV app and runs its UI test.

`release.yml` reuses a passing `tests.yml` run of its commit (by run conclusion) or calls
`tests.yml` as a reusable workflow. `main` has no branch protection or rulesets.

## Goals / Non-Goals

**Goals:**
- A job's name says which app or module it checks, so a red job points at the broken part.
- Readable names in the GitHub run list.

**Non-Goals:**
- iOS UI tests in CI, or other changes to what is tested.
- Changes to `release.yml` or the triggers.

## Decisions

### 1. Split into its own `ios` job instead of renaming `apple-tv`
The iOS build moves into a job `ios` with the same Xcode selection and FFmpeg cache restore as
`apple-tv`. On a cache hit the restore takes seconds. On a miss each job would build FFmpeg on
its own, but that happens only when `build-ffmpeg.sh` changes. The two jobs run in parallel, so
the run gets shorter.

- Rejected: renaming `apple-tv` to a neutral name such as `apps`. A red `apps` job still does not
  say which app broke, and the log has to be read anyway.
- Rejected: one job with a matrix over platforms. The steps differ too much (Apple TV has a
  simulator setup and a UI test, iOS is build-only), so a matrix would be mostly `if:` branches.
- Rejected: `ios` waiting for `apple-tv` with `needs:` so that FFmpeg is built only once on a
  cache miss. This makes every run longer to save time in the rare miss.

### 2. Job ids stay short, display names say what runs
The ids `core`, `apple-tv` and `ios` stay as they are or are new. They appear in URLs and in the
artifact name `apple-tv-uitest-results`. A `name:` gives the readable label:
- `core`: "FernsyCore tests (macOS, tvOS)"
- `apple-tv`: "Apple TV app and UI test"
- `ios`: "iPhone and iPad app"

In a `release.yml` run, which calls `tests.yml` as a reusable workflow, they show up as
"tests / Apple TV app and UI test" and so on.

### 3. On a cache miss, only `apple-tv` saves the FFmpeg cache
Both jobs build FFmpeg when it misses, but only `apple-tv` saves it, as it does now. Two saves
of the same key would race, and the second one fails with "cache already exists". `ios` only
restores the cache, and builds FFmpeg itself on a miss.

## Risks / Trade-offs

- One more runner job per push, about 5 to 10 minutes of runner time for Xcode selection, the
  cache restore and the iOS build. It is accepted for a clear failure signal and a shorter run.
- An old link or note that names "job `apple-tv`" for the iOS build gets out of date.
  DEVELOPMENT.md is updated as part of this change.
