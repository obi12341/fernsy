## MODIFIED Requirements

### Requirement: Pages in two languages
The site SHALL offer home, support, pricing, terms of service, refund policy, privacy and imprint
pages in German (`/`) and English (`/en/`), using the company data of mobilistics GmbH. Every
page's footer SHALL link pricing, terms, refunds, privacy and imprint in its language.

#### Scenario: English support page
- **WHEN** someone opens https://www.fernsy.app/en/support.html
- **THEN** the English support page is shown

#### Scenario: Legal links from the home page
- **WHEN** Paddle's reviewer opens https://www.fernsy.app
- **THEN** the footer links the pricing page, the terms, the refund policy, the privacy policy and the imprint with the contact address

### Requirement: Privacy statement matches the app
The privacy pages SHALL state that Fernsy collects no data and only connects to the
provider the user configures, and SHALL describe what Fernsy Cloud, the assistant and the
purchase through Apple or through Paddle on the website process.

#### Scenario: Privacy URL in App Store Connect
- **WHEN** App Review opens the privacy URL
- **THEN** it describes the app's actual data handling

#### Scenario: Purchase on the website
- **WHEN** a buyer reads the privacy page before subscribing on fernsy.app
- **THEN** it names Paddle as reseller, what Paddle processes and that the checkout page loads Paddle's script

## ADDED Requirements

### Requirement: Terms, prices and refunds for the web purchase
The pricing page SHALL show the price of Fernsy Cloud as it is in the live Paddle catalog,
including VAT, with what it includes. The terms SHALL describe the app, Fernsy Cloud, the
subscription's term and cancellation, and the user's responsibility for what they record. The
refund policy SHALL state when a website purchase is refunded and that App Store purchases are
refunded by Apple. The checkout page SHALL link the terms and the refund policy.

#### Scenario: Refund request in the first two weeks
- **WHEN** a buyer asks for a refund 5 days after the first payment on the website
- **THEN** the refund policy promises the full first payment back

#### Scenario: Refund of a renewal
- **WHEN** a subscriber asks for a refund of a monthly renewal
- **THEN** the refund policy says renewals are not refunded unless the law requires it, and that cancelling stops the next one
