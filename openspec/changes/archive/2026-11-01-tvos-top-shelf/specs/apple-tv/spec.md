## ADDED Requirements

### Requirement: Top Shelf content
When Fernsy's icon has focus in the top row of the Home Screen, its Top Shelf SHALL show rows
from what Start shows: Continue Watching (backdrop, title, progress), the channels of Start's
live row (logo, channel, show on now) and finished recordings, each row only when it has items.
Hidden channels and adult content SHALL NOT appear, as on Start.

#### Scenario: Signed in with content
- **WHEN** the user has a film in progress and favorite channels, and focuses Fernsy's icon on the Home Screen
- **THEN** the Top Shelf shows a Continue Watching row with the film and a row with the favorite channels

#### Scenario: Hidden channel
- **WHEN** a favorite channel is hidden in Fernsy
- **THEN** it does not appear in the Top Shelf

#### Scenario: Kept current
- **WHEN** the user stops a film at a new position and returns to the Home Screen
- **THEN** the Top Shelf shows the film with its new progress

### Requirement: Top Shelf actions
Selecting a tile in the Top Shelf, by a click or with the Play button, SHALL open Fernsy and
play the item: a film or episode from its resume position, a channel live, a recording from
where the user stopped, as a click on Start's Continue Watching does.

#### Scenario: Continue a film
- **WHEN** the user selects a film in the Top Shelf's Continue Watching row
- **THEN** Fernsy opens and the film plays from its resume position

#### Scenario: Play a channel
- **WHEN** the user selects a channel tile
- **THEN** Fernsy opens and the channel plays full screen

### Requirement: Static Top Shelf image
Without content to show (no account, nothing in the rows, or before Fernsy ran once), the Top
Shelf SHALL show a designed image of Fernsy's landscape across the full width with the app's
name, not the stand-in. Debug builds SHALL show the same image with their "DEV" band.

#### Scenario: Fresh install
- **WHEN** Fernsy was installed but never opened, and its icon gets focus
- **THEN** the Top Shelf shows the designed image

#### Scenario: Signed out
- **WHEN** the user signs out of every account
- **THEN** the Top Shelf shows the designed image and none of the previous items
