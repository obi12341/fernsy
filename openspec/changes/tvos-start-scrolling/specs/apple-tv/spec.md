## ADDED Requirements

### Requirement: Fluid Start on Apple TV
Moving through Start with the remote SHALL stay fluid with a large catalog (30,000 films,
12,000 channels): scrolling SHALL NOT rebuild Start's rows, which are built once per change of
what they show (catalog, resume positions, recordings, guide, Jellyfin), and rows below the
screen SHALL be built when they come near it.

#### Scenario: Scrolling down a large catalog
- **WHEN** the account has 30,000 films and the user moves down Start row by row and back up
- **THEN** the screen follows without visible stutter, and the backdrop fades as before

#### Scenario: A row changes
- **WHEN** a film is watched halfway while Start is open
- **THEN** Continue Watching shows it when the user returns to Start, without the other rows being rebuilt
