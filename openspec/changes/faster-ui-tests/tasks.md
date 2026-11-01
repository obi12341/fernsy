# Tasks

Runs against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo,
set by `launchDemo`). Classes without playback run in the test VM (`scripts/vm.sh`), playback
classes on the host (no hardware video decoding in the VM).

## 1. Baseline

- [ ] 1.1 `scripts/uitest-times.sh <xcresult>`: duration per test and per class from a result bundle
- [ ] 1.2 Baseline: a full Apple TV run (VM for non-playback, host for playback classes); numbers into design.md

## 2. App switches (debug builds)

- [ ] 2.1 `IPTV_OPEN=<fernsy:// link>`: passed to `TVModel.handle(url:)` at launch
- [ ] 2.2 `IPTV_TAB=<tab>`: selects the Apple TV tab at launch
- [ ] 2.3 DEVELOPMENT.md: both switches

## 3. Test helpers

- [ ] 3.1 `FernsyUITestCase`: `tab(_:_:)` (English and German labels), `focus(_:in:moves:)` waiting for focus changes, `waitFor(_:value:timeout:)`; failure messages name the focused element
- [ ] 3.2 Convert the classes that only need a screen to `IPTV_OPEN`/`IPTV_TAB` and the helpers (first `DetailPagesUITests`, `SearchUITests`, `LibraryUITests`; measure; then the rest), keeping navigation tests on the remote
- [ ] 3.3 Remove fixed sleeps except where time is the subject; each converted class passes three times in a row

## 4. Measure and decide

- [ ] 4.1 After-run with the same script; per-class numbers next to the baseline in design.md
- [ ] 4.2 Decide on parallel workers (`--parallel <n>` in the scripts) from the numbers; implement only if it pays
- [ ] 4.3 `openspec validate --all --strict`

## Workflow follow-up

- Archive (no spec deltas), merge into `main` and push with the user's consent. No release-note
  trailers: nothing users notice.
