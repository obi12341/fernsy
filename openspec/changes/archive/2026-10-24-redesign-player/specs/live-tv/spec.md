## MODIFIED Requirements

### Requirement: Zapping
In the player, ↑/↓ (and Page Up/Down) SHALL switch to the previous/next channel of the
category the channel was started from, wrapping around. A channel banner shows number,
logo, name with tags, the current show with its progress and what follows; tuning waits
until key presses stop.

#### Scenario: Pressing ↓ three times quickly
- **WHEN** the user presses ↓ three times within a second
- **THEN** the banner follows each press and only the third channel is tuned
