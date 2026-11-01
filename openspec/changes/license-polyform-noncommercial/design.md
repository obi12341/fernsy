## Context

The baseline (`2026-10-20-establish-baseline`, "Repository and license") chose GPLv3 so that
"closed commercial forks are not possible". The GPL only forbids *closed* forks: anyone may
still sell a build of the code as long as they publish their source. That is the new reason
for reopening the decision (see proposal.md - Why).

All commits in the repository are by the user (mobilistics GmbH holds the rights), so no
other contributor has to agree to the change. FFmpeg is built separately into
`Vendor/ffmpeg` under the LGPL 2.1 and dynamically linked; its headers in `CFFShim` keep their
own LGPL notices.

## Goals / Non-Goals

**Goals:**
- From the change on, the repository is licensed so that personal and other non-commercial
  use, changes and sharing are allowed and commercial use is not.
- The README, DEVELOPMENT.md and the agent context say the same.

**Non-Goals:**
- Changing what earlier releases were published under.
- Any change to the app, its credits or the build.

## Decisions

### 1. PolyForm Noncommercial License 1.0.0
Written for software, short, and widely used for exactly this split: any non-commercial
purpose (personal use, hobby projects, research, charities, schools, public institutions) is
allowed, including changes and redistribution under the same terms; commercial use is not.
The licensor (mobilistics GmbH) is not bound by it and keeps selling Fernsy. `LICENSE` holds the
unchanged license text from polyformproject.org (`1.0.0.txt`) and nothing else: the user did not
want a "Required Notice" copyright line in it; README and DEVELOPMENT.md name mobilistics GmbH.

Rejected alternatives:
- **Keep GPLv3:** allows others to sell builds; the reason for this change.
- **Creative Commons BY-NC(-SA) 4.0:** Creative Commons advises against its licenses for
  software (no patent or source terms), and "NonCommercial" there is broader and vaguer.
- **Business Source License 1.1:** built around a change date to an open-source license and
  production-use grants for services; Fernsy is an app, and an automatic switch back to an
  open license is not wanted.
- **PolyForm Personal Use or Strict:** Personal Use excludes non-profit organizations and
  schools, Strict also forbids changes and sharing; both are narrower than "personal use
  anything goes" asked for.
- **Commons Clause added to GPLv3:** combines two texts with contradicting terms; legally
  unclear and confusing for readers.

### 2. Earlier releases stay GPLv3, and the docs say so
A license that was granted cannot be withdrawn for copies people already have. README and
DEVELOPMENT.md state that releases up to v1.6.0 remain under GPLv3, so nobody is misled. The
first release under the new license is 2.0.0.

### 3. The CLA condition stays
Contributions still need an agreement that lets mobilistics use them commercially (App Store
sales); the non-commercial license alone does not grant that for third-party code.

### 4. Wording: "source-available", not "free software"
The README currently says "free software". PolyForm Noncommercial is not an open-source
license in the OSI sense, so the README and DEVELOPMENT.md say "source-available" and describe
the terms in one plain sentence instead.

## Risks / Trade-offs

- [Someone forks the last GPLv3 commit and sells it] → cannot be prevented for that code;
  later work is under the new license only.
- [PolyForm's "commercial" boundary is a legal question in edge cases] → the license's own
  definitions apply; the user may have a lawyer review it (out of scope here).
- [GitHub shows "Other" as license and fewer contributors join] → accepted; contributions
  needed a CLA already.
- [LGPL obligations for FFmpeg] → unchanged: the libraries stay dynamically linked and
  replaceable, their source is linked in the credits, and PolyForm Noncommercial does not
  forbid the changes and reverse engineering the LGPL requires to permit.

## Migration Plan

Merge before tagging v2.0.0, so the 2.0.0 tag carries the new license. Rollback: restore the
GPLv3 `LICENSE` and texts (only for future versions; copies under PolyForm stay PolyForm).
