# Tasks

## 1. Workflows

- [x] 1.1 `tests.yml`: push only to `main`, `paths-ignore` for `openspec/**` and `**/*.md` (design 1); header comment updated.
- [x] 1.2 `release.yml`: `reuse` job with the lookup and polling (design 2), `tests` only when needed and the build jobs' conditions (design 3, 4); `permissions: actions: read` where needed.
- [x] 1.3 `DEVELOPMENT.md`: when tests run and how the nightly reuses them.

## 2. Verification

- [x] 2.1 `actionlint` (or `gh workflow view` parsing) on both files without errors.
- [x] 2.2 After merging: the merge push starts one test run on `main`; the change branch's push starts none (`gh run list`).
- [x] 2.3 Nightly dispatched for that commit after its tests passed: the run shows `reuse` → `passed=true`, `tests` skipped, `dmg` built (`gh run view`).
- [ ] 2.4 A spec-only commit on `main` starts no test run; a nightly dispatched for it runs `tests` itself (only if such a commit comes up anyway; not forced).
