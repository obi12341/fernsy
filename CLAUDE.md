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
- Build, release and debug switches: see README.md.
