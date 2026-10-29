# Proposal

## Why

Since `ios-app`, the `apple-tv` job in `tests.yml` also builds the iPhone and iPad app. A red
`apple-tv` job no longer says which app broke. Someone reading the run has to open the log to
find out whether the Apple TV UI test or the iOS build failed. The job's name no longer matches
what it does.

## What Changes

- The iPhone and iPad simulator build moves out of the `apple-tv` job into its own job, `ios`. It
  runs in parallel on the same runner label and restores FFmpeg from the same cache.
- `apple-tv` keeps only what its name says: the Apple TV app build and its UI test.
- Every job in `tests.yml` gets a readable display name, shown in the GitHub run list:
  - `core`: "FernsyCore tests (macOS, tvOS)"
  - `apple-tv`: "Apple TV app and UI test"
  - `ios`: "iPhone and iPad app"
- The header comment of `tests.yml` and the CI line in DEVELOPMENT.md (› iPhone and iPad) name
  the new job.

Out of scope:
- iOS UI tests in CI. They stay local, as `ios-app` decided.
- Renaming steps or jobs in `release.yml`. Its jobs (`prepare`, `reuse`, `tests`, `dmg`,
  `appstore`, `publish`) already say what they do.
- Changing what is tested or when. The triggers, the reuse of a passing run by `release.yml`
  and the path filters stay as they are.

## Capabilities

### New Capabilities

### Modified Capabilities
- `distribution`: "iPhone and iPad app in CI" says the iOS build is its own CI job, named for
  the iPhone and iPad app, so its failure is not reported as an Apple TV failure.

## Impact

- `.github/workflows/tests.yml`: a new `ios` job, the iOS step removed from `apple-tv`, and
  `name:` added to each job.
- `DEVELOPMENT.md`: the reference to "job `apple-tv`" for the iOS build.
- `release.yml` is unaffected. It checks only the conclusion of the whole `tests.yml` run (by
  commit, see `reuse`), not job names. The tests are also called as a reusable workflow, where
  all jobs must pass.
- `main` has no branch protection or rulesets, so no required check refers to a job name.
- Cost: one more runner job per push. It runs in parallel with `apple-tv`, so the run finishes
  sooner than with the iOS build inside `apple-tv`.
