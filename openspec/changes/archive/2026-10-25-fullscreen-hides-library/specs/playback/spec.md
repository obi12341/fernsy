## ADDED Requirements

### Requirement: Library hidden during full screen
While the player window is in full screen, Fernsy SHALL hide its library windows, so that
switching back to Fernsy (⌘-Tab, Dock) shows the full-screen player. When the player leaves
full screen or closes, the hidden library windows SHALL return in their place without taking
focus from the player. Asking for the library meanwhile SHALL show the hidden window, not open
another one.

#### Scenario: Back to the player with ⌘-Tab
- **WHEN** the player is in full screen, the user switches to another app on the desktop and then back to Fernsy
- **THEN** macOS shows the full-screen player, not the library window

#### Scenario: Leaving full screen
- **WHEN** the user leaves full screen
- **THEN** the library window is back at its place, behind the player window

#### Scenario: Closing in full screen
- **WHEN** the user closes the player while it is in full screen
- **THEN** the library window comes back

#### Scenario: Library asked for during full screen
- **WHEN** the library is hidden and the user chooses "Fernsy öffnen" in the menu bar item
- **THEN** the hidden library window is shown and no second library window opens
