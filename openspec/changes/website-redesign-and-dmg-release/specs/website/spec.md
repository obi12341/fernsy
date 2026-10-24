## ADDED Requirements

### Requirement: Home page in the app's design
The home pages (German and English) SHALL follow the "Website" design from Claude Design: dark
background with a warm glow, app icon, headline and availability note, a hero image of the
player, a tabbed gallery of the main views, a "New in Fernsy" section, the feature overview
with the content notice, and a footer. Images SHALL be rendered from the design's mockups, and
the page SHALL work without JavaScript.

#### Scenario: Gallery tabs
- **WHEN** a visitor clicks "Filme" above the gallery
- **THEN** the gallery shows the film catalogue image with its caption

#### Scenario: Without JavaScript
- **WHEN** JavaScript is turned off
- **THEN** the page shows all sections, and the gallery shows its images one below the other

#### Scenario: Narrow screen
- **WHEN** the page is opened on a 390 pt wide phone
- **THEN** all sections fit the width without horizontal scrolling

### Requirement: Download from GitHub Releases
The home pages SHALL offer a download button that links to the newest release's `Fernsy.dmg`
on GitHub, with the system requirement shown next to it. The other pages SHALL use the same
header, colours and footer.

#### Scenario: Downloading
- **WHEN** a visitor clicks "Für Mac laden"
- **THEN** the browser downloads `Fernsy.dmg` of the newest GitHub release
