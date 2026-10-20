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
