# Proposal

## Why

The README is the first page people see on GitHub, and many of them find Fernsy there before
the website or the App Store. Today it reads like working notes for developers and agents:
build steps, release secrets and dozens of `IPTV_*` debug switches. It should sell Fernsy to
new users instead, and keep the developer material in one place that contributors and agents
can still find.

## What Changes

- Rewrite `README.md` as a product page: app icon and headline, what Fernsy is, the main
  features with images, Jellyfin, recordings and timeshift, privacy, system requirements,
  download (GitHub release DMG, App Store availability as on the website), and the note that
  Fernsy contains no channels and sells no subscriptions.
- End the README with a short "Contributing" section: GPLv3 and the CLA condition for pull
  requests, how to build in two lines, and a link to the developer documentation. The license
  notice (GPLv3, LGPL FFmpeg) stays in that last part.
- Move all developer content that is in the README today (build, releases and nightlies,
  Sparkle, demo server, Jellyfin notes, player internals, debug switches) unchanged in substance
  into a new `DEVELOPMENT.md`.
- Point every reference to "README › Release/Updates" at `DEVELOPMENT.md`: `CLAUDE.md` and the
  messages in `.github/workflows/release.yml`.

Out of scope:
- Changes to the website, the App Store texts or the images (the README reuses the website's
  existing English images from `website/assets/`).
- A German README; the README is English and links to the German website.
- New content in the developer documentation beyond what moves there; no `CONTRIBUTING.md`
  of its own.
- Any change to the app.

## Capabilities

### New Capabilities
- `project-readme`: what the repository's README is for (a product page for new users), what
  it has to contain, where the contribution section sits, and where developer documentation
  lives instead.

### Modified Capabilities
<!-- none -->

## Impact

- `README.md` (rewritten), new `DEVELOPMENT.md`.
- `CLAUDE.md` (pointer to the developer documentation).
- `.github/workflows/release.yml` (three error/warning messages name the new file).
- No code, build or release behavior changes.
