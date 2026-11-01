# Tasks

No code changes, so no demo-server run or `IPTV_*` switch is needed; verification is reading
the files, `openspec validate --all --strict` and the GitHub repository page after the push.

## 1. License texts

- [x] 1.1 Replace `LICENSE` with the unchanged PolyForm Noncommercial License 1.0.0 text from https://polyformproject.org/licenses/noncommercial/1.0.0.txt, with no notice line added (decided with the user)
- [x] 1.2 README's contributing section: "source-available" instead of "free software"; personal and non-commercial use, changes and sharing allowed, commercial use not; releases up to v1.6.0 remain under GPLv3; FFmpeg stays LGPL 2.1; the CLA sentence reworded for the new license (mobilistics sells Fernsy)
- [x] 1.3 DEVELOPMENT.md "License": the same terms and the GPLv3 note for earlier releases; contributions paragraph without the GPL wording
- [x] 1.4 `openspec/config.yaml` context: "under the PolyForm Noncommercial License 1.0.0" instead of "under GPLv3"

## 2. Check

- [x] 2.1 No text outside FFmpeg, archived changes and the GPLv3 note still says Fernsy is under the GPL (`grep -rIi 'GPL\|General Public'` without build folders, `Vendor`, `CFFShim`, `openspec/changes/archive`)
- [x] 2.2 `openspec validate --all --strict` passes
- [ ] 2.3 After the push to `main`, GitHub's repository page shows the new license and the README renders the section correctly

## Workflow follow-up

- Archive on `change/license-polyform-noncommercial`, merge into `main` and push with the
  user's consent, then tag v2.0.0 (the first release under the new license). No
  release-note trailers: nothing in the app changes.
