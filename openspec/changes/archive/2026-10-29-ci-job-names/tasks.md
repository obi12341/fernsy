# Tasks

## 1. Workflow

- [x] 1.1 `tests.yml`: give each job a `name:` ("FernsyCore tests (macOS, tvOS)", "Apple TV app and UI test", "iPhone and iPad app").
- [x] 1.2 `tests.yml`: add a job `ios` (`runs-on: xcode-27`, a timeout of 40 min) with checkout, Xcode selection, the FFmpeg cache restore, an FFmpeg build on a miss (without saving, design 3) and the "iPhone and iPad app build" step. Remove that step from `apple-tv`.
- [x] 1.3 `tests.yml`: update the header comment so it names the three jobs.

## 2. Docs

- [x] 2.1 DEVELOPMENT.md › iPhone and iPad: replace "job `apple-tv`" with job `ios`.

## 3. Verification

- [x] 3.1 Check the YAML locally (`actionlint` via nix: clean for tests.yml, ignoring the custom `xcode-27` label) and run `openspec validate --all --strict`.
- [ ] 3.2 After the merge to `main`: the push's Tests run shows three jobs with their names, `ios` and `apple-tv` run in parallel, and all pass. The Apple TV UI test runs against the demo server as before (`scripts/tv-uitest.sh`).
