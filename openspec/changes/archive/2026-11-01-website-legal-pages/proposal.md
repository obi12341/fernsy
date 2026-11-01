# Proposal

## Why

Paddle approves www.fernsy.app for live checkouts only when the site links to a pricing page,
terms of service, a privacy policy and a refund policy, and when its prices match the live
catalog. The site has a privacy page that names only the App Store, and nothing else of the
three.

## What Changes

- New pages in German and English: pricing (`preise.html`, `en/pricing.html`), terms of service
  (`agb.html`, `en/terms.html`) and refund policy (`erstattung.html`, `en/refunds.html`).
- Every footer links pricing, terms, refunds, privacy and imprint; the checkout page links the
  terms and the refund policy next to the purchase.
- The privacy pages name Paddle for website purchases and say that the checkout page loads
  Paddle.js.
- Refunds are kept as narrow as the law and Paddle allow: 14 days on the first payment,
  renewals not refunded, cancellation at the end of the period; App Store purchases follow
  Apple.

Out of scope: a lawyer's review (the user has the texts checked before or after launch), cookie
banners (the site still sets no cookies of its own), and the price change itself
(`cloud-pricing-100gb`), whose numbers the pricing page already shows.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `website`: the page set grows by pricing, terms and refunds; the privacy statement covers the
  web purchase.

## Impact

- `website/*.html`, `website/en/*.html` (new pages, footers, privacy, checkout page).
- Paddle live catalog: a 3.49 € monthly price on Fernsy Cloud, used by the prod worker, so the
  catalog matches the pricing page.
