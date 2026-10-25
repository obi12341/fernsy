# Design

## Context

`README.md` (309 lines) holds a two-line product intro and then only developer material. That
material is referenced from `CLAUDE.md` ("see README.md") and from three messages in
`.github/workflows/release.yml` ("README › Release", "README › Updates"). Archived designs
(establish-baseline, direct-updates, release-from-tags, release-notes-from-commits) chose to
document setup steps "in the README"; this change keeps those notes, only in a new file.

The website (`website/`) already has the product copy in German and English and English
images (`website/assets/en-*.webp`, rendered from the design mockups, ~45-150 KB each) plus
the icon (`website/assets/icon.png`).

## Goals / Non-Goals

**Goals:**
- A README that works as a landing page on GitHub, built from what the website already says.
- No developer knowledge lost: everything moves to `DEVELOPMENT.md` with the same headings.

**Non-Goals:**
- Rewording or restructuring the developer notes while moving them.
- New images, a video embed or badges beyond what helps a buyer.

## Decisions

- **English README, link to the German site.** GitHub's audience is international and the
  repo's working language is English; the website covers German. Rejected: a bilingual README
  (twice as long, the pitch gets buried) and a German-only README (unreadable for most GitHub
  visitors).
- **Reuse the website's English images by relative path** (`website/assets/en-*.webp`, centred
  icon via HTML `<p align="center">`). GitHub renders WebP and relative paths, and the images
  stay in one place. Rejected: copying images into a new folder (two copies drift apart) and
  linking to www.fernsy.app URLs (breaks in forks and offline clones).
- **Copy follows the website** (headline "Your IPTV subscription as a real Mac app", feature
  groups, content notice, privacy) so there is one voice and no claim the website does not make.
  The hero video is not embedded: GitHub does not play repository MP4 files inline; the README
  links to the website instead.
- **`DEVELOPMENT.md`, not `CONTRIBUTING.md`.** Most of the moved content is maintainer
  material (signing secrets, Sparkle keys, App Store uploads), not contribution guidance. The
  short contribution terms stay at the end of the README as the user asked. Rejected: a
  separate `CONTRIBUTING.md` (a third place repeating the CLA note) and `docs/` (git-ignored).
- **Move, don't rewrite.** The developer sections move verbatim with their headings; only the
  title, a one-line intro and internal "see README" phrases change. This keeps the change
  reviewable with a diff and keeps archived design references valid in substance.

## Risks / Trade-offs

- [README claims drift from the app as features change] → the spec requires claims to match
  the website; changes that alter the website's feature list should update the README in the
  same change.
- [Agents and old links look for build steps in the README] → `CLAUDE.md` points to
  `DEVELOPMENT.md`, and the README's last section links there.
- [Images are design mockups, not screenshots] → the website uses the same images; accepted.
