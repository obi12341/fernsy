## MODIFIED Requirements

### Requirement: Contributing section last
The README SHALL end with a short contributing section: the PolyForm Noncommercial License
1.0.0 (personal and other non-commercial use allowed, commercial use not) with the separately
licensed LGPL FFmpeg, a note that releases up to v1.6.0 remain under GPLv3, the condition
that pull requests need a contributor license agreement, the build in a few commands, and a
link to the developer documentation. No developer content SHALL appear above it.

#### Scenario: Developer looks for build steps
- **WHEN** a developer scrolls to the end of the README
- **THEN** they find the contribution terms and a link to `DEVELOPMENT.md`

#### Scenario: Someone wants to sell a build of Fernsy
- **WHEN** a reader checks whether they may sell their own build of the current source
- **THEN** the contributing section and `LICENSE` say that commercial use is not allowed

#### Scenario: Someone builds Fernsy for personal use
- **WHEN** a reader checks whether they may build, change and use Fernsy for themselves
- **THEN** the contributing section says that personal, non-commercial use is allowed
