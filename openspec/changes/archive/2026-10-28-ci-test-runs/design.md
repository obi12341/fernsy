# Design

## Context

- `tests.yml` runs on `push` to `main` and `change/**`, on `pull_request`, and as
  `workflow_call` from `release.yml`; jobs `core` and `apple-tv` (about 20–26 minutes on the
  `xcode-27` runner). Its concurrency group is `tests-<sha>` without cancelling.
- `release.yml`: `prepare` → `tests` (calls `tests.yml` for `prepare.outputs.sha`) → `dmg`,
  `appstore` (`needs: [prepare, tests]`) → `publish`. A job whose `needs` was skipped is skipped
  too unless its `if` says otherwise.
- The archive flow pushes the change branch and `main` together; changes are tested locally in
  full before that (OpenSpec tasks "full suite green").

## Goals / Non-Goals

**Goals:**
- One full test run per merge; a nightly for a tested commit builds at once.
- The gate stays: nothing is published from a commit without a passing run.

**Non-Goals:**
- Faster or sharded UI tests; the nightly's schedule.

## Decisions

1. **`tests.yml` triggers.** `push: branches: [main]` with `paths-ignore: ['openspec/**',
   '**/*.md']`; `pull_request` and `workflow_call` stay. A workflow file change is not ignored, so
   CI edits are tested. Rejected: running only FernsyCore on change branches (the compromise
   discussed; the user chose no branch runs, local full runs cover branches).

2. **Reuse in `release.yml`.** A new job `reuse` after `prepare` (ubuntu, `actions: read`)
   lists the runs of `tests.yml` for the commit
   (`gh api repos/$REPO/actions/workflows/tests.yml/runs?head_sha=$SHA`): a completed `success`
   sets `passed=true`; a run in progress is polled every 60 s (up to 70 minutes) and its
   conclusion decides; none, or a failed one, sets `passed=false`. Runs started by the release
   itself (`event == workflow_call` shows as the caller's run, not listed) do not count.

3. **`tests` only when needed.** `tests: if: needs.reuse.outputs.passed != 'true' && channel !=
   'skip'`. The build jobs get `if: ${{ !failure() && !cancelled() && <channel condition> }}` so a
   skipped `tests` job (because a run was reused) does not skip them, while a failed one still
   stops them.

4. **A failed reused run blocks.** If the reused run failed, `passed=false` and the release
   runs the tests again (a flaky failure gets a second chance; a real one fails again and blocks).
   Rejected: failing the release at once (it would make one flaky run block the nightly).

## Risks / Trade-offs

- [A broken change branch is noticed only at the merge] → the local full run before pushing
  stays the rule; pull requests are still tested.
- [GitHub lists runs by `head_sha` with a delay of seconds] → the `reuse` job waits 20 s before
  its first lookup (always: simpler than checking the push time, and cheap on ubuntu).
- [Wrong `if` on the build jobs publishes untested code] → verified with a dry run of the
  workflow logic: one dispatch for a commit with a passing run (builds without tests), one for a
  spec-only commit (runs tests).
