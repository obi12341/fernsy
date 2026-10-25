# Tasks

## 1. Collecting notes

- [x] 1.1 Workflow step (bash): collect `Release-Note-de` and `Release-Note-en` for the range (release: previous `v*` tag..tag; nightly: last `v*` tag..sha), oldest first, without duplicates. Fall back to commit subjects without "Mark …", "Archive …" and merges, with a `::warning::` for releases. Write the results to `notes-de.txt` and `notes-en.txt`.

  Verify locally:
  - the range v1.1.0..v1.1.1 yields the fallback, because no trailers exist yet;
  - a test commit with trailers on a scratch branch yields its notes.

## 2. Release text and Sparkle

- [x] 2.1 `publish`: release text with "Neu in Fernsy X.Y.Z", "What's new", without the former signing line. A release drafted by hand stays unchanged. Stop reading `RELEASE_NOTES.md`. Nightly: trailer notes on top of the commit list.
- [x] 2.2 `Appcast`: German notes in `<archive>.html`. Check whether `generate_appcast` 2.10 takes localized `<archive>.<lang>.html`; otherwise add `<description xml:lang="en">` with a Python step after generation. Verify locally with the throwaway key and the test DMG from earlier: the appcast has both descriptions with `xml:lang`, still parses, and the signature is unchanged.

## 3. Rule and documentation

- [x] 3.1 Add the `CLAUDE.md` section "Release notes in commits" (when/when not, format, example, both languages).
- [x] 3.2 README release section: trailers instead of `RELEASE_NOTES.md`, the warning, and the fallback.
- [x] 3.3 Memory: a feedback entry on release-note trailers.

## 4. Verification

- [x] 4.1 This change's own commits carry trailers where they make sense; the workflow itself is internal, so there is none for it. Push, run a nightly (`gh workflow run`), and check that its GitHub text and appcast look right.
- [x] 4.2 Edit the 1.1.1 release text by hand (`gh release edit v1.1.1`) with the user-visible points.
- [x] 4.3 `openspec validate release-notes-from-commits --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
