## MODIFIED Requirements

### Requirement: Program guide on iPhone and iPad
Programm SHALL show a guide grid for the chosen source that scrolls in both directions by touch:
channels with logo and name stay at the left edge, shows on a time axis with the time now marked,
past shows dimmed and running ones highlighted. Tapping a running show SHALL play its channel;
tapping a later show SHALL show its details. Rows without listings, still loading, or with gaps
SHALL show bars there that play the channel when tapped. It SHALL scroll without stalls at any
size.

#### Scenario: Playing from the guide
- **WHEN** the user taps a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Channel without listings
- **WHEN** the provider sends no listings for a channel
- **THEN** its row shows the bar "Keine Programmdaten", and tapping it plays the channel

#### Scenario: Scrolling a large guide
- **WHEN** the source has hundreds of channels, some with a week of archive, and the user scrolls
  the guide up, down and back in time on an iPad
- **THEN** the grid follows the finger, the app stays responsive, and only the rows that came on
  screen request their listings
