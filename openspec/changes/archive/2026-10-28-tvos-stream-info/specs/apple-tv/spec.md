## ADDED Requirements

### Requirement: Technical information on Apple TV
Settings › Wiedergabe SHALL offer "Technische Infos", off by default. While it is on, every
player on Apple TV SHALL show a panel with the rows of the Mac's technical information overlay
and its two-minute buffer chart, updated once per second, without taking the focus or hiding
the player overlay. The setting SHALL be kept across launches.

#### Scenario: Turning it on
- **WHEN** the user turns on "Technische Infos" and plays a live channel
- **THEN** the panel shows codec, resolution, decoder, buffer and reconnects and updates every second

#### Scenario: Reconnect counted
- **WHEN** a live stream reconnects and repeats packets it already sent
- **THEN** the panel counts the seamless reconnect and the dropped duplicates, as on the Mac

#### Scenario: Off by default
- **WHEN** the app is installed and a film plays
- **THEN** no panel is shown

#### Scenario: Remote still works
- **WHEN** the panel is shown and the user clicks to open the player overlay
- **THEN** the overlay opens and takes the focus as without the panel
