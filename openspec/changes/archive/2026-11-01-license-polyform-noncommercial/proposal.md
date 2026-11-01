# Proposal

## Why

Fernsy's source is public under GPLv3. The GPL allows anyone to take the code, build it and
sell it as their own app, as long as they publish their source. mobilistics GmbH does not want
that: anyone may use, study and change Fernsy for personal, non-commercial purposes, but
commercial use stays with mobilistics. The license should change before the 2.0.0 release,
so 2.0.0 is the first version under the new terms.

## What Changes

- **BREAKING (licensing):** `LICENSE` becomes the PolyForm Noncommercial License 1.0.0, the
  official text without an added notice line. Fernsy is no longer free/open-source
  software but source-available.
- README's contributing section and DEVELOPMENT.md's "License" section describe the new
  license: personal and other non-commercial use, changes and sharing are allowed; commercial
  use is not. They say that versions released before the change (up to v1.6.0) remain under
  GPLv3 for whoever got them.
- The contributor license agreement note stays: mobilistics sells Fernsy, so pull requests
  still need an agreement that allows this.
- `openspec/config.yaml`'s project context names the new license.
- The bundled FFmpeg libraries stay under the LGPL 2.1; the app's credits do not change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-readme`: the contributing section names the PolyForm Noncommercial 1.0.0 license
  instead of GPLv3.

## Impact

- Files: `LICENSE`, `README.md`, `DEVELOPMENT.md`, `openspec/config.yaml`.
- No code, build or app behavior changes; the App Store and DMG builds are unaffected.
- GitHub shows the repository's license from `LICENSE` (it may show "Other" instead of
  GPL-3.0).

## Out of scope

- Relicensing or withdrawing earlier releases: what was published under GPLv3 stays GPLv3.
- FFmpeg's license, the in-app credits and the distribution spec's LGPL requirement.
- Legal review: the user may have a lawyer check the choice; this change only applies it.
- A commercial license offer (for example a contact for companies); can follow later.
