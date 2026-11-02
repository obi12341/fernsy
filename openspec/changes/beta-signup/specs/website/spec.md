## MODIFIED Requirements

### Requirement: Pages in two languages
The site SHALL offer home, support, beta, pricing, terms of service, refund policy, withdrawal,
privacy and imprint pages in German (`/`) and English (`/en/`), using the company data of
mobilistics GmbH. Every page's footer SHALL link beta, pricing, terms, refunds, withdrawal, privacy
and imprint in its language.

#### Scenario: English support page
- **WHEN** someone opens https://www.fernsy.app/en/support.html
- **THEN** the English support page is shown

#### Scenario: Legal links from the home page
- **WHEN** a payment provider's reviewer opens https://www.fernsy.app
- **THEN** the footer links the pricing page, the terms, the refund policy, the withdrawal information, the privacy policy and the imprint with the contact address

### Requirement: Privacy statement matches the app
The privacy pages SHALL state that Fernsy collects no data and only connects to the
provider the user configures, and SHALL describe what Fernsy Cloud, the assistant, the
purchase through Apple or through Stripe on the website, and the beta sign-up process.

#### Scenario: Privacy URL in App Store Connect
- **WHEN** App Review opens the privacy URL
- **THEN** it describes the app's actual data handling

#### Scenario: Purchase on the website
- **WHEN** a buyer reads the privacy page before subscribing on fernsy.app
- **THEN** it names Stripe as payment processor, what Stripe and mobilistics process, and that the checkout page loads Stripe's script

#### Scenario: Beta sign-up
- **WHEN** a visitor reads the privacy page before signing up for the beta
- **THEN** it says that the address and name go to Apple for TestFlight and what the server keeps for the rate limit

## ADDED Requirements

### Requirement: Beta from the home page
The home pages SHALL link the beta page next to the DMG download, naming iPhone, iPad and Apple TV,
as long as the apps are not in the App Store.

#### Scenario: Beta button
- **WHEN** a visitor opens https://www.fernsy.app
- **THEN** next to "Für Mac laden" a button leads to the beta page for iPhone, iPad and Apple TV
