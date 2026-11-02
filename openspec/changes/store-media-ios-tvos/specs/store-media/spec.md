## Purpose

The media for Fernsy's App Store product pages on iPhone, iPad and Apple TV: screenshots, app
previews and the header and search results images. They are produced from the real apps with the
demo server's fictional content, and can be produced again after every redesign.

## ADDED Requirements

### Requirement: Screenshots from the real apps
For each language (German, English) there SHALL be screenshots for iPhone (6.3", 1206 × 2622),
iPhone Duo (2007 × 2853), iPad 13" (2064 × 2752) and Apple TV (3840 × 2160), taken from the apps in
the simulator, signed in to the demo server, with the app in that language. One command SHALL
produce all of them into `dist/store/`.

#### Scenario: Producing the screenshots
- **WHEN** the screenshot command runs on the Mac with the simulators installed
- **THEN** `dist/store/<platform>/<language>/` holds numbered PNGs at exactly the sizes above, without alpha channel, in German and English

#### Scenario: Content language
- **WHEN** the German screenshots are taken
- **THEN** the app's texts and the demo channels, programs and posters are German

### Requirement: What the screenshots show
The screenshots SHALL show the apps' main scenes (live TV with the program guide, a film page, the
player, search, recordings, and on Apple TV the Start page) with demo content only, and no debug
overlays, simulator chrome, prices or website addresses.

#### Scenario: Checking a set
- **WHEN** the iPad screenshots for English are looked through
- **THEN** each shows one of the main scenes with fictional demo content and a clean status bar

### Requirement: German and English complete
Every screenshot, app preview, header and search image and every store text SHALL exist in German
and in English, each with its texts and demo content in that language. The media command SHALL fail
when a file is missing for one of the two languages.

#### Scenario: One language missing
- **WHEN** the English iPad shots were taken but the German ones failed
- **THEN** the command ends with an error naming the missing German files

### Requirement: App previews
For each language there SHALL be one app preview of 15 to 30 seconds for iPhone (886 × 1920), iPad
(1200 × 1600) and Apple TV (1920 × 1080), recorded from the app in the simulator with demo content,
at 30 fps with a stereo audio track, showing the app in use without simulator chrome.

#### Scenario: Preview for Apple TV
- **WHEN** the preview command has run
- **THEN** `dist/store/tv/<language>/preview.mp4` is 1920 × 1080, 30 fps, between 15 and 30 seconds long, and App Store Connect accepts it

### Requirement: Header and search results images
For each language there SHALL be a product page header image (3840 × 1646) and a search results
image (3840 × 2560) for the iOS app, without alpha channel, showing Fernsy's own screens and one
short line of text in that language. They SHALL suit an age rating of 4+ and contain no prices,
discounts or website addresses; the important content SHALL lie in the centre so both crops keep
it. The Apple TV app gets none, since App Store Connect does not offer the placement there.

#### Scenario: Header in German
- **WHEN** the header image for German is opened
- **THEN** it is 3840 × 1646, its line of text is German, and it shows only demo content

#### Scenario: Search card crop
- **WHEN** the search results image is checked in App Store Connect's preview
- **THEN** the line of text and the app screens are fully visible
