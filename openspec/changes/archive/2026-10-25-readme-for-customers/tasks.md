# Tasks

## 1. Developer documentation

- [x] 1.1 Create `DEVELOPMENT.md` with every section of today's README below the intro (Build, Release incl. GitHub Actions, release notes and Sparkle, Demo server, Jellyfin, Development, License details) moved verbatim; verify with a word diff (`git diff --no-index --word-diff`) that only the title, the intro line and "README" self-references changed
- [x] 1.2 Point `CLAUDE.md` ("Build, release and debug switches") and the three messages in `.github/workflows/release.yml` at `DEVELOPMENT.md`; verify `grep -rn "README" CLAUDE.md .github` finds no stale reference

## 2. Product README

- [x] 2.1 Rewrite `README.md` as the product page (icon, pitch, download/availability matching `website/en/index.html`, feature sections with `website/assets/en-*.webp` images, Jellyfin, recordings and timeshift, privacy, content notice, links to www.fernsy.app and /en/); verify every referenced image path exists (`grep -o 'website/assets/[^)"]*' README.md | xargs ls`)
- [x] 2.2 Add the closing "Contributing" section (GPLv3 + LGPL FFmpeg, CLA condition, build in a few commands, link to `DEVELOPMENT.md`) as the last part; verify no build, release or `IPTV_*` content appears above it (`grep -n "IPTV_\|xcodebuild\|secret" README.md`)
- [x] 2.3 Check every feature and availability claim against the website and the current specs (App Store "coming soon", macOS 27+, Apple silicon); verify by reading both side by side
- [x] 2.4 Render the README locally as GitHub would (`gh api markdown` with `mode=gfm` on the file, opened in a browser) and let the user review the rendered page before archiving

## 3. Validation

- [x] 3.1 Run `openspec validate --all --strict` and verify it passes (no app build or `IPTV_*` run needed: no code changes)
