# Spec Delta

## MODIFIED Requirements

### Requirement: Home page in the app's design
The home pages (German and English) SHALL follow the "Website" design from Claude Design: dark
background with a warm glow, app icon, headline and availability note, a hero video in the
page's language, a tabbed gallery of the main views, a "New in Fernsy" section, the feature
overview with the content notice, and a footer. Images SHALL be rendered from the design's
mockups, and the page SHALL work without JavaScript.

#### Scenario: Gallery tabs
- **WHEN** a visitor clicks "Filme" above the gallery
- **THEN** the gallery shows the film catalogue image with its caption

#### Scenario: Without JavaScript
- **WHEN** JavaScript is turned off
- **THEN** the page shows all sections, and the gallery shows its images one below the other

#### Scenario: Narrow screen
- **WHEN** the page is opened on a 390 pt wide phone
- **THEN** all sections fit the width without horizontal scrolling

## ADDED Requirements

### Requirement: Hero video plays only on request
Each home page SHALL show the promo video in its language in the hero frame, in 16:9, with a
still frame from the video and a play button over it. The video SHALL NOT start, and its file
SHALL NOT be downloaded, before the visitor starts playback. After that, it plays with sound
and with the browser's controls for pause, seeking, volume and full screen.

#### Scenario: Opening the page
- **WHEN** a visitor opens https://www.fernsy.app/
- **THEN** the hero shows the still frame with a play button, nothing plays, and the video
  file is not requested

#### Scenario: Starting the video
- **WHEN** the visitor clicks the play button
- **THEN** the video starts from the beginning in the hero frame, the play button disappears
  and the browser's controls are available

#### Scenario: Keyboard
- **WHEN** a visitor tabs to the play button and presses Return or Space
- **THEN** the video starts as with a click

#### Scenario: Video without JavaScript
- **WHEN** JavaScript is turned off
- **THEN** the hero shows the still frame with the browser's controls, and the video plays
  when the visitor presses their play control

#### Scenario: Video on a phone
- **WHEN** a home page is opened on a 390 pt wide phone
- **THEN** the video fits the width and plays inline after a tap on Play

#### Scenario: English home page
- **WHEN** someone opens https://www.fernsy.app/en/ and clicks Play
- **THEN** the English video plays, with an English still frame and button label
