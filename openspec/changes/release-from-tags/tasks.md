# Tasks

## 1. Scripts

- [x] 1.1 `build-dmg.sh` and `build-appstore.sh`: optional `BUILD_VERSION` and `BUILD_NUMBER`, passed as `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` to `xcodebuild` without changing the project. `build-appstore.sh` skips its bump when `BUILD_NUMBER` is set. Verify with `bash -n`. Fernsy is not launched; the smoke test runs in CI.
- [x] 1.2 `build-appstore.sh`: with `ASC_KEY`, `ASC_KEY_ID` and `ASC_ISSUER`, add `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` to archive and export.

## 2. Workflow

- [x] 2.1 `prepare` job:
  - triggers: tags, `schedule` 02:00 UTC, and `workflow_dispatch` with `channel` (`nightly`, `appstore-test`);
  - `fetch-depth: 0`;
  - check the tag pattern and that the tag is on main;
  - version and build number;
  - skip the nightly when main is unchanged;
  - outputs `channel`, `version`, `build` and `sha`.
- [x] 2.2 `dmg` job: as today, with `BUILD_VERSION`/`BUILD_NUMBER` and without the old version check. The DMG name depends on the channel. Upload it as an artifact for `publish`.
- [x] 2.3 `appstore` job (tag and `appstore-test`):
  - FFmpeg cache;
  - API key as a temporary file;
  - `build-appstore.sh` with `UPLOAD=1`, or with `export` for `appstore-test`;
  - clean up the key in `always()`.
- [x] 2.4 `publish` job:
  - **tag:** create the release, or attach to an existing one with `--clobber`;
  - **nightly:** delete the old pre-release and its tag, create a new pre-release at `sha` with the commit list since the last `v*` tag.
- [x] 2.5 Check the YAML with Ruby, and that secrets appear only in the steps that need them.

## 3. Documentation

- [x] 3.1 README "Release": tag → DMG + App Store upload; Nightly; creating a release in the web interface; the Admin key requirement; the 1.0 warning. Remove the old "tag must match MARKETING_VERSION".

## 4. Verification (after the user replaced the key with an Admin key)

- [x] 4.1 Run `workflow_dispatch` with `channel: nightly`. The "Nightly" pre-release appears with a notarized DMG and version `nightly-<date>` (build = commit count), and `releases/latest` stays unaffected (`gh api …/releases/latest` returns no nightly). Download it and check it with `spctl`/`stapler validate`, without launching it.
- [x] 4.2 A second manual nightly replaces the first one (only one pre-release `nightly`).
- [x] 4.3 Run `workflow_dispatch` with `channel: appstore-test`. The archive and the export with cloud signing succeed, and the `.pkg` is signed by "3rd Party Mac Developer Installer"/"Apple Distribution" (log). Nothing is uploaded.
- [x] 4.4 The first real release tag stays the user's step after 1.0 is approved. Document it, and keep this task open until the user confirms it.
- [x] 4.5 `openspec validate release-from-tags --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees. Archive `website-redesign-and-dmg-release` first, because its release requirement is the base here.
