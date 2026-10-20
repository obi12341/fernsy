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
- Build, release and debug switches: see README.md.
