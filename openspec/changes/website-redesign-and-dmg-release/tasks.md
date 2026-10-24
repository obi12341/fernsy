# Tasks

## 1. Images from the design

- [x] 1.1 Fetch `Website.dc.html`, the imported mockup files, `support.js` and `assets/fernsy-icon.png` through DesignSync into the scratchpad, never into the repo. Try one harness page with headless Chrome (`Player` variant `live`). If that fails, pause and report.
- [x] 1.2 Render all images at 2× and convert them to WebP or JPEG into `website/assets/`:
  - hero `player-live`;
  - gallery `programm`, `player-live-edge`, `sender`, `filme`, `film-details`, `serien`;
  - rows `jellyfin`, `aufnahmen`;
  - `icon` from `fernsy-icon.png`.

  Check every image and note the sizes.

## 2. Pages

- [x] 2.1 Rewrite `style.css` with the design's colours and components: nav, hero with glow, buttons, tabs, image frames, rows, cards, notice and footer. Responsive down to 390 pt, with no horizontal scrolling.
- [x] 2.2 `index.html` in German, following `Website.dc.html`:
  - texts taken over;
  - download button "Für Mac laden", with the system requirement and "Bald im Mac App Store";
  - gallery tabs with an inline script and a no-JS fallback;
  - alt texts for all images.
- [x] 2.3 `en/index.html` with an English translation of the same texts ("Download for Mac", "Coming soon to the Mac App Store").
- [x] 2.4 Support, privacy and imprint pages (de and en): new header, nav and footer; content unchanged.
- [x] 2.5 Remove the old screenshots (`de-*.jpg`, `en-*.jpg`) once nothing references them. Run a link check over all pages with a local `python3 -m http.server`: no 404s.
- [x] 2.6 Verification: headless Chrome screenshots of `index.html` and `en/index.html` at 1440 and 390 px width, of the gallery with a different tab active, and with JS off (`--blink-settings=scriptEnabled=false`). Compare them with the design.

## 3. DMG and release

- [ ] 3.1 `scripts/build-dmg.sh`:
  - API-key notarization (`NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`);
  - `ENABLE_HARDENED_RUNTIME=YES` when signing with an identity;
  - a check after signing that `flags` contains `runtime`.

  Locally, verify with the existing Apple Development build: the DMG still builds, and the runtime flag is shown.
- [x] 3.2 Add `.github/workflows/release.yml` as in design decision 4:
  - the secret check;
  - the version check;
  - the FFmpeg cache;
  - the temporary keychain;
  - build, notarize and staple;
  - the verification;
  - the release with `Fernsy.dmg` and `Fernsy-<version>.dmg`;
  - cleanup in `always()`.
- [x] 3.3 Validate the workflow locally with `actionlint`, if it is installed; otherwise check the YAML syntax with Python. Make sure no step prints a secret: no `set -x` around the secrets, and file permissions are set to 600.
- [x] 3.4 README section "Release": create the Developer ID certificate and the App Store Connect API key, set the five repository secrets, and push a tag. Include the warning not to tag before 1.0 is approved.
- [ ] 3.5 Manual steps by the user, outside my reach:
  - create the certificate and the key;
  - set the secrets;
  - start the workflow manually (`workflow_dispatch`);
  - check the downloaded artifact on another Mac (Gatekeeper, keychain, recording to ~/Movies).

  I document this, and the task stays open until the user confirms it.

## 4. Spec and wrap-up

- [x] 4.1 `openspec validate website-redesign-and-dmg-release --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees. Pushing to main publishes the website immediately through `pages.yml`.
- Before merging, agree on the order with the user. The download button must not go live before a release with `Fernsy.dmg` exists. The options are to merge without the button first, or to release first and then merge.
