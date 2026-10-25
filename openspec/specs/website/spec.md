# website Specification

## Purpose
The product website www.fernsy.app with the pages the App Store requires (marketing,
support, privacy) and the legal imprint, in German and English.

## Requirements

### Requirement: Pages in two languages
The site SHALL offer home, support, privacy and imprint pages in German (`/`) and English
(`/en/`), using the company data of mobilistics GmbH.

#### Scenario: English support page
- **WHEN** someone opens https://www.fernsy.app/en/support.html
- **THEN** the English support page is shown

### Requirement: Hosting and domain
The site SHALL be published from `website/` via GitHub Pages on www.fernsy.app with enforced
HTTPS; fernsy.app redirects to www.fernsy.app.

#### Scenario: Bare domain
- **WHEN** someone opens https://fernsy.app
- **THEN** they end up on https://www.fernsy.app

### Requirement: Privacy statement matches the app
The privacy pages SHALL state that Fernsy collects no data and only connects to the
provider the user configures.

#### Scenario: Privacy URL in App Store Connect
- **WHEN** App Review opens the privacy URL
- **THEN** it describes the app's actual data handling

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

### Requirement: Download from GitHub Releases
The home pages SHALL offer a download button that links to the newest release's `Fernsy.dmg`
on GitHub, with the system requirement shown next to it. The other pages SHALL use the same
header, colours and footer.

#### Scenario: Downloading
- **WHEN** a visitor clicks "Für Mac laden"
- **THEN** the browser downloads `Fernsy.dmg` of the newest GitHub release
