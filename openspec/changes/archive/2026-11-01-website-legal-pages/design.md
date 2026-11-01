# Design

## Context

Paddle is merchant of record for purchases on fernsy.app: it sells Fernsy Cloud to the buyer under
its own buyer terms, collects VAT and handles refunds and chargebacks. Paddle's go-live checklist
asks for public terms of service, privacy policy and refund policy pages, a contact address
reachable from the home page, and prices that match the live catalog. The site's pages share
`style.css` and the `main.text` layout of the privacy and imprint pages.

## Goals / Non-Goals

**Goals:** pages that pass Paddle's website review and say plainly what the buyer gets.

**Non-Goals:** a lawyer-grade contract; prices per country (Paddle localizes at checkout).

## Decisions

### 1. Refunds: 14 days on the first payment, nothing after
The user wants refunds excluded as far as possible. Consumers in the EU have a 14-day right of
withdrawal for online contracts; for a digital service it lapses only with the consumer's express
consent to start at once, which Paddle's checkout, not our page, would have to collect. Paddle as
seller honours refunds under its buyer terms and reviews seller refund policies. So the policy
grants the full first payment back on request within 14 days, refunds no renewals unless the law
requires it, and lets subscribers cancel any time to the end of the paid month.
Rejected: "no refunds" (contradicts the statutory right of withdrawal and Paddle's buyer terms,
and puts the domain approval at risk); refunds pro rata on cancellation (more than the law asks).

### 2. Pages under fixed names in both languages
`preise.html` / `en/pricing.html`, `agb.html` / `en/terms.html`, `erstattung.html` /
`en/refunds.html`, like `datenschutz.html` / `en/privacy.html`, so Paddle's form gets stable URLs.

### 3. The pricing page names one price
3.49 € a month including VAT, 100 GB, 300 assistant requests (the numbers of
`cloud-pricing-100gb`). The live Paddle catalog gets a 3.49 € price that the prod worker sells,
so site and catalog match before the review. The App Store shows Apple's price in the app.
Rejected: prices loaded from Paddle on the page (the review reads the static page, and the site
avoids external scripts outside the checkout page).

## Risks / Trade-offs

- [The texts are drafted without a lawyer] → They follow the usual German B2C clauses; the
  user has them reviewed, and changes need no code.
- [The App Store still sells at 2.99 € until App Store Connect changes] → The pricing page
  speaks of the website purchase; `cloud-pricing-100gb` aligns the App Store.

## Migration Plan

Merge into `main`; the Website workflow publishes the pages. Then the user enters the URLs in
Paddle's website approval.
