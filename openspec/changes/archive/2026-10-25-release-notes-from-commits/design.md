# Design

## Context

`.github/workflows/release.yml` builds releases from `v*` tags and the nightly from main.

**Release text:**
- In the `publish` job it comes from `RELEASE_NOTES.md` when present.
- Otherwise it is one standard sentence.
- The nightly lists `git log --format='- %s (%h)'` since the last `v*` tag.

**Sparkle notes:**
- The `Appcast` step in the `dmg` job writes `<archive>.html` with a `<ul>`: lines of
  `RELEASE_NOTES.md` or commit subjects.
- `generate_appcast --embed-release-notes` embeds it as `<description>`.
- The appcast itself is not signed; only the DMG has an EdDSA signature (`sparkle:edSignature`).
  Editing the XML afterwards therefore does not break anything.

**Commits** are written mostly by the assistant, in English, with a subject line and a body.
Many are internal: task marks, archives, CI.

The release for 1.1.1 is running now (or is done) with the standard text.

## Goals / Non-Goals

**Goals:**
- Readable notes in German and English for GitHub and Sparkle, without a manual step at
  release time.
- A forgotten note shows up at release time, not with the users.
- The rule survives sessions.

**Non-Goals:**
- App Store Connect "What's New".
- AI-written notes.
- Blocking commits.
- A changelog file in the repo.

## Decisions

### 1. Git trailers as the source

Trailers are `Release-Note-de: <sentence>` and `Release-Note-en: <sentence>` at the end of the
commit message, next to `Co-Authored-By`. One sentence per language, in plain user words. A
commit may carry several pairs (several user-visible points).

Reading them:

```
git log --format='%(trailers:key=Release-Note-de,valueonly,separator=%x0A)' <range>
```

The empty lines are removed. The order is oldest first (`--reverse`), duplicates are removed.

Rejected:
- **A changelog file (`CHANGELOG.md` or `changelog.d/` fragments):** merge conflicts with
  parallel branches, and one more file per change.
- **A section in the OpenSpec proposal:** bug fixes without a change would be missing (the
  sidebar fix in 1.1.1).
- **AI summaries at release time:** not deterministic, they need an API key, and they publish
  unreviewed.

### 2. Ranges

- **Release `vX.Y.Z`:** `<previous v* tag>..<tag>`, where the previous tag is
  `git describe --tags --match 'v[0-9]*' --abbrev=0 <tag>^`. Without an earlier tag, the whole
  history.
- **Nightly:** `<last v* tag>..<sha>`, the same base as today's commit list.

### 3. Output

- **GitHub release:** "## Neu in Fernsy X.Y.Z" with the German notes as a list, then
  "## What's new" with the English ones. The former standard line about signing and
  notarization is dropped: it tells users nothing.
  - A release drafted by hand keeps its text, as before.
  - `RELEASE_NOTES.md` is no longer read, so there is one source.
- **Sparkle:** `generate_appcast` writes the appcast with the German HTML as before. Then a
  small Python step (standard library `xml.etree`, or a careful text insertion) adds a second
  `<description xml:lang="en">` and marks the first as `xml:lang="de"`. Sparkle picks the
  description that matches the preferred languages and falls back to the first.
  - Checked during implementation: `generate_appcast` 2.10 ignores `<archive>.<lang>.html`
    (it wrote only the German description), while the Sparkle framework does read
    `xml:lang`. So `scripts/appcast-notes.py` adds the English description and checks that
    the XML parses and the enclosure signature is unchanged.
- **Collecting** lives in `scripts/release-notes.sh` rather than inline in the workflow, so it
  can be run locally. The `dmg` job runs it once and passes `out/notes/` to `publish` in the
  artifact, so a release warning appears only once.
- **Nightly text on GitHub:** it keeps the full commit list (testers want details), with the
  trailer notes on top when present.

### 4. Warning and fallback

When a release range has no trailer in one language:
- the run writes `::warning::No Release-Note-de trailers since vX.Y.Z – falling back to commit
  subjects`;
- the notes become the commit subjects, without subjects starting with "Mark " or "Archive "
  and without merge commits.

For a nightly without trailers there is no warning (normal for internal commits), only the
commit list.

### 5. Keeping the rule

- **`CLAUDE.md`:** a short section "Release notes in commits" with when (user-visible
  behaviour, fixes users notice), when not (task marks, archives, CI, refactoring, specs),
  the format, an example, and that both languages are required.
- **Memory:** a feedback entry pointing to it, with the reason ("the user wants notes without
  a manual step; the trailers are the source").
- **README:** the same in short, under Release, for the user's own commits.

### 6. 1.1.1

Its release is or will be published with the standard text. After this change, I edit its
GitHub text once by hand (`gh release edit v1.1.1 --notes-file`) with:
- the Recordings sidebar fix;
- automatic updates for the DMG build;
- nightly builds on request.

Its appcast stays as is: 1.1.1 has the old notes.

## Risks / Trade-offs

- **[Trailers only work when they are written]** → `CLAUDE.md`, memory, and a visible warning
  at release time.
- **[Merges and rebases]** → Trailers stay in the commits, and `git log` sees them through
  merges. Squash merges would have to carry the trailers over; they are not used here.
- **[Editing the appcast XML]** → The appcast is not signed, only the DMG, so the edit is
  safe. The workflow checks afterwards that the file still parses and still has
  `sparkle:edSignature`.
