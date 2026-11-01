# website Specification

## Purpose
The product website www.fernsy.app with the pages the App Store and the website purchase require
(marketing, support, pricing, terms, refunds, withdrawal, privacy) and the legal imprint, in German
and English.

## Requirements

### Requirement: Pages in two languages
The site SHALL offer home, support, pricing, terms of service, refund policy, withdrawal, privacy
and imprint pages in German (`/`) and English (`/en/`), using the company data of mobilistics
GmbH. Every page's footer SHALL link pricing, terms, refunds, withdrawal, privacy and imprint in
its language.

#### Scenario: English support page
- **WHEN** someone opens https://www.fernsy.app/en/support.html
- **THEN** the English support page is shown

#### Scenario: Legal links from the home page
- **WHEN** a payment provider's reviewer opens https://www.fernsy.app
- **THEN** the footer links the pricing page, the terms, the refund policy, the withdrawal information, the privacy policy and the imprint with the contact address

### Requirement: Hosting and domain
The site SHALL be published from `website/` via GitHub Pages on www.fernsy.app with enforced
HTTPS; fernsy.app redirects to www.fernsy.app.

#### Scenario: Bare domain
- **WHEN** someone opens https://fernsy.app
- **THEN** they end up on https://www.fernsy.app

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

### Requirement: Ordering on the checkout page
The checkout page SHALL show what is bought, the price including VAT, the monthly renewal and the
term before payment, SHALL ask the buyer to request the service to start before the withdrawal
period ends and to acknowledge the consequence, and SHALL label the payment button
"Zahlungspflichtig abonnieren" (English: "Subscribe and pay").

#### Scenario: Order summary and button
- **WHEN** a buyer opens the checkout page from the DMG
- **THEN** it shows Fernsy Cloud, 3,49 € per month including VAT, monthly renewal and cancellation, the start request, and the button "Zahlungspflichtig abonnieren"

### Requirement: Withdrawal information
The site SHALL publish the withdrawal information with the model withdrawal form for website
purchases, and the refund policy SHALL say how to cancel: "Manage Subscription" in the DMG or an
e-mail to mobilistics.

#### Scenario: Withdrawal from the footer
- **WHEN** a buyer clicks "Widerruf" in the footer
- **THEN** the withdrawal information with mobilistics' address and the model form is shown
