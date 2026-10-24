# appearance Specification

## Purpose
Fernsy's shared visual rules that are user-visible behaviour: dark and light appearance with the icon's violet accent, channel logos on tiles that stay readable, poster placeholders, and status marks that never rely on colour alone.

## Requirements

### Requirement: Dark and light appearance
Fernsy SHALL follow the system appearance (dark or light) with one set of colours defined
for both: the accent is the violet of the app icon (lighter in dark, darker in light for
contrast), red is used only for recording and live, amber for warnings and offline.

#### Scenario: Switching the system to light
- **WHEN** the user switches macOS to the light appearance while Fernsy is open
- **THEN** all windows switch to light colours, selections and main actions stay violet, and recording marks stay red

#### Scenario: Red is reserved
- **WHEN** a view needs to highlight a selection or a main action
- **THEN** it uses the accent, never red

### Requirement: Logo tiles
Channel logos SHALL be shown on a tile with the aspect ratio 13:8 and a fixed inner margin,
graphite in both appearances. A logo that is dark on a transparent background SHALL get a
light tile instead, decided by measuring the logo once. A channel without a logo SHALL show
its initials on the tile.

#### Scenario: White logo in the light appearance
- **WHEN** a white logo on a transparent background is shown in the light appearance
- **THEN** it sits on a graphite tile and stays readable

#### Scenario: Dark logo on a transparent background
- **WHEN** a channel's logo is black on a transparent background
- **THEN** it sits on a light tile

#### Scenario: Channel without a logo
- **WHEN** a channel named "Kanal Süd" has no logo
- **THEN** its tile shows "KS"

### Requirement: Poster placeholder
A poster that is missing or fails to load SHALL be replaced by the title set on a neutral
2:3 surface, so poster grids keep their rhythm.

#### Scenario: Film without a poster
- **WHEN** a film has no poster URL
- **THEN** its card shows the film's title on a neutral surface in the poster's place

### Requirement: Markers never rely on colour alone
Status markers (in the player, recording, scheduled, favourite, offline, hidden, live,
time behind live) SHALL always combine a symbol or text with their colour.

#### Scenario: Recording mark
- **WHEN** a channel is being recorded
- **THEN** its mark shows a red dot together with the text "REC"
