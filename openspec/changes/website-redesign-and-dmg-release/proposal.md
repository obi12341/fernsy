# Proposal

## Why

The website (`website/`) still has the old look: a blue-violet gradient and a plain
screenshot grid. It shows none of the features of 1.1:
- recordings;
- timeshift;
- Jellyfin;
- Picture in Picture;
- the menu bar;
- search.

Claude Design has a new home page in the app's redesigned style (`Website.dc.html` in the
"Fernsy Redesign" project). Its texts already describe the new features.

There is also no download outside the App Store. `scripts/build-dmg.sh` can sign and
notarize, but only on the user's Mac, and only an "Apple Development" certificate is
present. That certificate is not trusted on other Macs. A GitHub Action that builds the DMG
with Developer ID, notarizes and staples it, and publishes it as a release lets the website
offer a download that opens without a Gatekeeper warning.

## What Changes

- **New home page, German and English, following `Website.dc.html`:**
  - dark background (#111015) with a warm glow behind the hero;
  - the app icon, the headline and the App Store note;
  - a hero image of the player;
  - a screenshot gallery with tabs (Programm, Live-TV, Sender, Filme, Film-Details, Serien);
  - "Neu in Fernsy", with Jellyfin and Recordings as large rows and four small cards (Timeshift, Bild-in-Bild, Suche, Menüleiste);
  - "Alles, was Fernsy kann", with the content notice;
  - a closing section and the footer.

  The texts come from the design. The English page gets matching translations.
- **Images rendered from the design mockups.** The design embeds live mockups (Player,
  Programm, LiveTV, Filme, FilmDetail, SerieDetail, JellyfinStart, Aufnahmen). They are
  rendered once, locally and headless, to images (WebP/JPEG at 2× width) and stored in
  `website/assets/`. The old screenshots that are no longer used are removed.
- **Download button.** Next to "Bald im Mac App Store", the hero and the closing section
  offer "Für Mac laden" / "Download for Mac". It links to the latest GitHub release
  (`releases/latest/download/Fernsy.dmg`), with version and system requirement below it.
- **Support, privacy and imprint pages** get the new header, colours and footer. Their
  content stays.
- **GitHub Action `release.yml`:**
  - on a tag `v*` (and manually without publishing), on a GitHub-hosted macOS runner with
    Xcode 27;
  - builds LGPL FFmpeg from source and caches it by version;
  - builds the Release app with "Developer ID Application" and hardened runtime;
  - runs the existing smoke test;
  - creates, signs and notarizes the DMG with an App Store Connect API key, and staples it;
  - publishes it as a release asset `Fernsy.dmg`, plus `Fernsy-<version>.dmg`.

  Certificate and key come from repository secrets.
- **`build-dmg.sh` can also notarize with an API key** (`NOTARY_KEY`, `NOTARY_KEY_ID`,
  `NOTARY_ISSUER`) as well as with a keychain profile, so CI and local runs share one path.

Out of scope:
- Sparkle or another in-app updater.
- App Store builds in CI.
- Changes to the app.
- Its own download server.
- The first release itself. Pushing a tag stays the user's decision. 1.1 is not announced
  before 1.0 is approved.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `website`: new requirements "Home page in the app's design" and "Download from GitHub
  Releases".
- `distribution`: "DMG for direct installation" gains API-key notarization. New requirement
  "Release build in GitHub Actions".

## Impact

- `website/`:
  - `index.html`, `en/index.html` and `style.css` are rewritten;
  - support, privacy and imprint pages (de/en) get the new header and footer;
  - new images in `assets/`, old ones removed;
  - a small inline script for the gallery tabs, which also works without JS.
- `.github/workflows/release.yml` (new) and `scripts/build-dmg.sh` (API-key notarization,
  stable file name).
- Repository secrets (set up by the user):
  - `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD`;
  - `NOTARY_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER`.
- The user creates a "Developer ID Application" certificate (only the account holder can)
  and an App Store Connect API key with the Developer role.
- README: the release process.
