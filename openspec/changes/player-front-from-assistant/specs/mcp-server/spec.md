## ADDED Requirements

### Requirement: Player in front without taking focus
When the assistant or Siri starts playback, Fernsy SHALL show the player window in front of all
windows, also when it was open behind other windows or minimized, without activating Fernsy, so
keyboard focus stays in the app the user is using. While Picture in Picture runs, no player
window SHALL come forward.

#### Scenario: Playing from the Claude chat
- **WHEN** the user is typing in Claude Desktop and Claude calls `play` for a channel
- **THEN** the player window appears in front of the chat window and the chat keeps keyboard focus

#### Scenario: Player already open behind other windows
- **WHEN** the player window is open behind other apps' windows and the assistant plays another channel
- **THEN** the player window comes in front and shows the new channel

#### Scenario: Picture in Picture
- **WHEN** Picture in Picture runs and the assistant plays a channel
- **THEN** the channel plays in the PiP window and no player window comes forward
