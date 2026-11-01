## MODIFIED Requirements

### Requirement: Pages in two languages
The site SHALL offer home, support, pricing, terms of service, refund policy, withdrawal,
cancellation, privacy and imprint pages in German (`/`) and English (`/en/`), using the company
data of mobilistics GmbH. Every page's footer SHALL link pricing, terms, refunds, withdrawal,
cancellation, privacy and imprint in its language.

#### Scenario: English support page
- **WHEN** someone opens https://www.fernsy.app/en/support.html
- **THEN** the English support page is shown

#### Scenario: Legal links from the home page
- **WHEN** a payment provider's reviewer opens https://www.fernsy.app
- **THEN** the footer links the pricing page, the terms, the refund policy, the withdrawal information, the cancellation page, the privacy policy and the imprint with the contact address

### Requirement: Privacy statement matches the app
The privacy pages SHALL state that Fernsy collects no data and only connects to the
provider the user configures, and SHALL describe what Fernsy Cloud, the assistant and the
purchase through Apple or through Stripe on the website process.

#### Scenario: Privacy URL in App Store Connect
- **WHEN** App Review opens the privacy URL
- **THEN** it describes the app's actual data handling

#### Scenario: Purchase on the website
- **WHEN** a buyer reads the privacy page before subscribing on fernsy.app
- **THEN** it names Stripe as payment processor, what Stripe and mobilistics process, and that the checkout page loads Stripe's script

### Requirement: Terms, prices and refunds for the web purchase
The pricing page SHALL show the price of Fernsy Cloud as it is in the live Stripe catalog,
including VAT, with what it includes. The terms SHALL name mobilistics as seller and describe the
app, Fernsy Cloud, the term and cancellation, and the user's responsibility for what they record.
The refund policy SHALL state when a website purchase is refunded and that App Store purchases are
refunded by Apple. The checkout page SHALL link the terms, refunds and withdrawal information.

#### Scenario: Refund request in the first two weeks
- **WHEN** a buyer withdraws 5 days after subscribing on the website and asked for the service to start at once
- **THEN** the refund policy promises the first payment back minus the share for the 5 days used

#### Scenario: Refund of a renewal
- **WHEN** a subscriber asks for a refund of a monthly renewal
- **THEN** the refund policy says renewals are not refunded unless the law requires it, and that cancelling stops the next one

## ADDED Requirements

### Requirement: Ordering on the checkout page
The checkout page SHALL show what is bought, the price including VAT, the monthly renewal and the
term before payment, SHALL ask the buyer to request the service to start before the withdrawal
period ends and to acknowledge the consequence, and SHALL label the payment button
"Zahlungspflichtig abonnieren" (English: "Subscribe and pay").

#### Scenario: Order summary and button
- **WHEN** a buyer opens the checkout page from the DMG
- **THEN** it shows Fernsy Cloud, 3,49 € per month including VAT, monthly renewal and cancellation, the start request, and the button "Zahlungspflichtig abonnieren"

### Requirement: Withdrawal information and cancellation page
The site SHALL publish the withdrawal information with the model withdrawal form for website
purchases, and a cancellation page reachable from every footer, labelled "Verträge hier kündigen",
that cancels a website subscription by e-mail address without signing in (see `cloud-server`).

#### Scenario: Cancellation from the footer
- **WHEN** a subscriber clicks "Verträge hier kündigen" in the footer
- **THEN** a page asks for the e-mail address used for the purchase and offers a button "Jetzt kündigen"
