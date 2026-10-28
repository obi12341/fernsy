# Proposal

## Why

Each merge runs the full test workflow three times for the same code, about 20–26 minutes each
on macOS runners: once for the change branch's push (the archive commit), once for the push to
`main` (the merge commit), and once more when the nightly is started, because `release.yml`
calls `tests.yml` again for the commit `main` just tested (the shared concurrency group makes it
wait, then run). On 2026-10-28 the runs for one merge were 26, 22 and 22 minutes. Changes are
tested locally in full before they are pushed, so the branch run adds little.

## What Changes

- `release.yml` reuses a passing test run of the same commit: if `tests.yml` already succeeded
  for it, the release builds right away; if one is still running, it waits for its result; only
  without one does it run the tests itself. Nothing is published from a commit whose tests fail.
- `tests.yml` no longer runs on pushes to change branches; it runs on pushes to `main`, on pull
  requests, and when the release calls it.
- Pushes that change only specs and docs (`openspec/**`, Markdown files) do not start the tests;
  a nightly from such a commit runs them itself (no passing run exists for it).

Out of scope: making the UI tests faster or splitting them across runners; the schedule of the
nightly.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `distribution`: "Automated tests gate builds" and "Apple TV app in CI" run on pushes to `main`
  (not change branches), skip spec- and doc-only pushes, and a nightly or release reuses a
  passing run of the same commit.

## Impact

- `.github/workflows/tests.yml`: triggers (`branches: [main]`, `paths-ignore`).
- `.github/workflows/release.yml`: a job that looks up test runs for the commit (`actions: read`),
  the `tests` job only when needed, and the build jobs' conditions so a skipped `tests` job does
  not skip them.
- `DEVELOPMENT.md`: the CI section.
