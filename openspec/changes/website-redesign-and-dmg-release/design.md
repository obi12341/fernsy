# Design

## Context

**Website:**
- `website/` is static HTML (de at the root, en under `en/`) with one `style.css`, system
  fonts and no external resources.
- `.github/workflows/pages.yml` publishes it on every push to main that touches it.
- Today's look: a blue-violet gradient, a screenshot grid of six JPEGs per language, and
  feature cards.

**Design:** Claude Design project `7e8ce8af-…`, file `Website.dc.html`.
- Inline styles and the colours of the redesign: background #111015, cards #1C1B21, text
  #F3F2F7, accent #6C65F0/#B7B3FF.
- The images are live `dc-import` mockups from the other design files (`Player` variants
  `live` and `liveEdge`, `Programm`, `LiveTV`, `Filme`, `FilmDetail`, `SerieDetail`,
  `JellyfinStart`, `Aufnahmen`), scaled to the column width.
- The gallery switches tabs in script.
- The texts are German only.
- The footer credits "Big Buck Bunny" (the video still in the player mockup).

**DMG:**
- `scripts/build-dmg.sh`: Release build, then smoke test, then `hdiutil`, then optionally
  `codesign`, `notarytool` with a keychain profile, and `stapler`.
- FFmpeg (`Vendor/ffmpeg`, 20 MB) is not in git; `scripts/build-ffmpeg.sh` builds it from the
  ffmpeg.org source archive.
- The project needs Xcode 27 (deployment target macOS 27).
- The repo `obi12341/fernsy` is public. The only signing identity on the user's Mac is
  "Apple Development".

## Goals / Non-Goals

**Goals:**
- The home page looks like the design, in de and en.
- It loads fast, stays static and works without JS.
- A notarized DMG appears from a tag push, without the user's Mac.
- Secrets never land in the repo or in logs.

**Non-Goals:**
- An updater.
- CI App Store uploads.
- Redesigning the support, privacy and imprint content.
- A self-hosted runner.

## Decisions

### 1. Static HTML from the design, not the design runtime

The page is written by hand as semantic HTML. The design's inline styles move into
`style.css` as classes and custom properties for the design's colours.
`support.js` and `dc-import` are not shipped.

The gallery uses a small inline script that switches `hidden` on the panels and
`aria-selected` on the tabs. Without JS, all six images show one below the other with their
captions, because the panels are not hidden in the HTML.

The texts are taken from the design, and the English pages get a translation of them.

Rejected:
- **Publishing `Website.dc.html` with `support.js`:** it is an editor runtime, loads React,
  and renders the mockups in the visitor's browser. That is heavy and fragile, and it is
  not meant for production.

### 2. Images rendered from the mockups, headless

The design files and `support.js` are fetched through the DesignSync MCP into the scratchpad.
They stay out of the repo. A small harness page per image `dc-import`s exactly one mockup at
its size (1280×720 for the player, 1280×820 for the others).

Rendering steps:
1. Serve the files on `localhost` with `python3 -m http.server`.
2. Render each harness with headless Chrome:
   `--headless=new --screenshot --window-size=1280,820 --force-device-scale-factor=2`.
3. Convert the images to WebP (`cwebp`, or JPEG via `sips` if cwebp is missing), at quality
   80 and 2560 px wide.
4. Store them in `website/assets/` as `<view>.webp`, used with `<img width height>` and
   `loading="lazy"` (except the hero).

The mockups are German. For the English pages, a script translates the texts of copies of the
mockup files (UI labels, show and film titles, dates, decimal commas in ratings and sizes) and
renders them as `en-<view>.webp`. Channel names stay, because they are fictional brand names.
Pitfall: a decimal-comma rule must only touch ratings and sizes, never CSS values like
`rgba(255,255,255,…)`; and later word rules must not hit earlier translations ("From Start"
became "From Home").

This is done once, locally, and the result is committed. Neither CI nor the website renders
anything.

Rejected:
- **Real app screenshots:** the user chose the design mockups.
- **Rendering in CI:** that would need the design files in the repo or a login to Claude
  Design in CI.

If headless rendering of the mockups fails (for example, `support.js` needs the editor), I
pause and report before choosing another way.

### 3. Download links to GitHub's "latest" asset

The button points to `https://github.com/obi12341/fernsy/releases/latest/download/Fernsy.dmg`.
Every release uploads its DMG also under the stable name `Fernsy.dmg`, so the website needs no
update per release. The version is shown on the release page, not on the website, so no
JavaScript or API call is needed.

"Bald im Mac App Store" stays as the second, quiet element until the App Store link exists.

### 4. Release workflow `release.yml`

**Triggers:**
- `push: tags: ['v*']`: build and publish the release;
- `workflow_dispatch`: build only, uploaded as a workflow artifact.

**Runner:** `macos-26` or the newest hosted image, with `xcode-select` set to Xcode 27. The
first step checks `xcodebuild -version`. Without Xcode 27 it fails with a clear message; a
self-hosted runner is then a later option.

**Steps:**
1. **Check secrets.** All five must be present, otherwise the run fails and names the missing
   ones. Secrets never appear in `echo`; values go only into files with `umask 077`.
2. **Version check.** The tag `vX.Y` must match `MARKETING_VERSION`.
3. **FFmpeg.** Cache `Vendor/ffmpeg` by a key made of `FFMPEG_VERSION` and the hash of
   `scripts/build-ffmpeg.sh`. On a cache miss, run `scripts/build-ffmpeg.sh`, which installs
   `nasm`/`pkg-config` via Homebrew if needed. Its LGPL check stays active.
4. **Signing identity.** Create a temporary keychain with a random password, import
   `DEVELOPER_ID_P12`, and set `set-key-partition-list` so codesign can use it without a
   prompt.
5. **Build, notarize and staple** with `SIGN_IDENTITY="Developer ID Application: … (B8YT7FNB66)"`
   and the API key (`NOTARY_KEY` as a temporary .p8 file). This is the same
   `scripts/build-dmg.sh` that runs locally.
6. **Verify:**
   - `codesign --verify --deep --strict`;
   - `codesign -dv` contains `flags=…runtime`;
   - `spctl -a -t open --context context:primary-signature` on the DMG;
   - `xcrun stapler validate`.
7. **Release.** Copy to `Fernsy.dmg` and create the release with
   `gh release create "$TAG" --title "Fernsy X.Y" --notes-file …` and both files. The notes
   are the release's what's new from a file in the repo (`docs/` is git-ignored, so
   `RELEASE_NOTES.md` is used if present; otherwise a short default text).
8. **Clean up:** delete the keychain and the key file, even when a step failed.

**Permissions:** `contents: write`, only for the release job.

Rejected:
- **fastlane/match:** too heavy for one certificate.
- **Committing Vendor/ffmpeg:** 20 MB of binaries in git, and it would undermine the LGPL
  build record.
- **Notarizing with an Apple ID and app-specific password:** an API key can be revoked on
  its own and needs no 2FA session.

### 5. `build-dmg.sh` notarizes with an API key too

`NOTARY_KEY` (path to the .p8), `NOTARY_KEY_ID` and `NOTARY_ISSUER` are passed to
`notarytool submit --key --key-id --issuer`. `NOTARY_PROFILE` keeps working.

Signing a Developer ID build sets `ENABLE_HARDENED_RUNTIME=YES` explicitly. Notarization
requires it, and the script must not depend on the project setting.

## Risks / Trade-offs

- **[Hosted runners may not have Xcode 27 yet]** → The run fails clearly at the start. The
  fallback (self-hosted or waiting) is the user's choice.
- **[The FFmpeg build takes about 10–15 minutes on a cache miss]** → It is cached by version
  and script hash.
- **[The sandboxed app outside the App Store]** → Developer ID allows the sandbox, and the
  entitlements stay the same. The task list checks that the keychain group and the Movies
  access work in a DMG install.
- **[The mockups show invented data, not the real app]** → The user chose this. The images
  are labelled as views, not as screenshots.
- **[Translated mockups drift from the design]** → They are rendered from copies, and the
  German originals stay the source. After design changes, both languages are rendered again
  with the same script.
- **[The download link returns 404 until the first release exists]** → Every push to main
  publishes the website at once. The download button therefore only goes live together with,
  or after, the first release. Until then the page is merged with the button left out, or
  with the merge held back; that order is the user's decision at archive time.
- **[A public 1.1 DMG before 1.0 is approved in the App Store]** → No release happens without
  the user pushing a tag. The task list explicitly leaves the first tag to them.
