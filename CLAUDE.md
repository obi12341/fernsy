# Fernsy – working notes for Claude

This repo uses OpenSpec (`openspec/`) to keep behavior and decisions traceable.

- Before changing behavior, read the affected specs (`openspec list --specs`,
  `openspec show <spec> --type spec`) and the constraints in `openspec/config.yaml`
  (single-stream account, demo server for stream tests, LGPL-only FFmpeg, sandbox, German +
  English UI).
- Why things are the way they are: `openspec/changes/archive/*/design.md` (decisions with
  rejected alternatives). Do not reopen a recorded decision without a new reason.
- New features or behavior changes go through a change: `/opsx:propose` (proposal, spec
  deltas, design, tasks), implement with `/opsx:apply`, then `/opsx:archive` so
  `openspec/specs/` stays the current truth. Bug fixes that do not change specified
  behavior need no change, but notable pitfalls belong in the related design.md.
- Validate with `openspec validate --all --strict`.
- Git: one branch per change (`change/<change-name>`). Apply, verify (including any manual
  checks the user has to do) and archive on that branch, so the archive commit lands with the
  code. Only then merge into `main` and push – `main` always has code and
  `openspec/specs/` in sync. Releases (App Store builds, DMGs) are built from `main`.
  Commit, merge and push only when the user agrees.
- Build, release and debug switches: see DEVELOPMENT.md. README.md is the product page for
  new users (keep developer content out of it; see the project-readme spec).

## Release notes in commits

Release texts and Sparkle's update notes are collected from commit trailers
(`scripts/release-notes.sh`); there is no manual step at release time.

- A commit with a change users notice (new behavior, a fix they would see) ends with one
  sentence per language in plain user words, next to `Co-Authored-By`. Both languages are
  required; several pairs are fine for several points.
- Internal commits carry none: task marks, archives, CI, refactoring, specs, docs.
- Example:

  ```
  Make Recordings selectable in the sidebar while a recording runs

  Release-Note-de: „Aufnahmen“ in der Seitenleiste lässt sich während einer Aufnahme wieder anklicken.
  Release-Note-en: "Recordings" in the sidebar can be clicked again while a recording runs.
  Co-Authored-By: …
  ```
