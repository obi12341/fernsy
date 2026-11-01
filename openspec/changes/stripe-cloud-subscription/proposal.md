# Proposal

## Why

Paddle's domain review of fernsy.app on 2026-11-01 refused the account ("Digital Content/
Streaming Services"), so the DMG cannot sell Fernsy Cloud through Paddle. mobilistics GmbH already
has a contract with Stripe. With Stripe, mobilistics sells the subscription itself: Stripe takes
the payment, mobilistics is the seller with the duties that come with it (VAT, invoices,
withdrawal, cancellation button).

## What Changes

- The DMG's purchase uses Stripe instead of Paddle: the checkout page on fernsy.app shows Stripe's
  payment form (card, Apple Pay, Google Pay, SEPA where Stripe offers them) with our own order
  summary and a button labelled "Zahlungspflichtig abonnieren" / "Subscribe and pay"; the worker
  creates the subscription for the account named by the signed checkout token.
- VAT through Stripe Tax; the price stays 3.49 € a month including VAT.
- "Manage Subscription" in the DMG opens Stripe's customer portal.
- **New:** a cancellation page on fernsy.app ("Vertrag hier kündigen") that cancels a website
  subscription without signing in, as German law requires for subscriptions sold online.
- **New:** withdrawal information and model withdrawal form; consent to immediate start in the
  checkout. Refunds: withdrawal within 14 days (minus the days used when the buyer asked to start
  at once), no refunds for renewals.
- Terms, pricing, refund and privacy pages name Stripe and mobilistics as seller.
- **BREAKING (internal):** Paddle is removed from worker, apps, website and docs. Only sandbox test
  subscriptions exist on Paddle; nothing in a release depends on it.

Out of scope: the App Store purchase (unchanged), other plans or a yearly price, a lawyer's
review of the texts (the user arranges it), invoices beyond Stripe's own receipts.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cloud-server`: subscription check with Stripe instead of Paddle; managing a website
  subscription through Stripe's portal; cancelling a website subscription without signing in.
- `recording-cloud`: the DMG sells through Stripe on fernsy.app.
- `website`: pages for withdrawal and cancellation; terms, prices, refunds and privacy for
  mobilistics as seller with Stripe.

## Impact

- `cloud-server/`: `paddle.js` → `stripe.js` (signature check, subscription mapping, API calls),
  routes under `/v1/checkout`, `/v1/stripe/notifications`, `/v1/subscription/portal`,
  `/v1/subscription/cancel`; `deploy.sh` secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
  `STRIPE_PUBLISHABLE_KEY`, `STRIPE_PRICE_ID`, `STRIPE_ENV`); tests; README.
- FernsyCore/FernsyShared: `PaddleCloudStore` → provider-neutral `WebCloudStore`,
  `Account.isPaddle` → `isWebPurchase`, failure names; tests.
- Mac (`DIRECT_DISTRIBUTION`) texts that name Paddle; iOS/TV note conditions; German strings.
- `website/`: `cloud.html` (Stripe.js Payment Element), new withdrawal and cancellation pages,
  terms, pricing, refunds, privacy, footers.
- Stripe account (user): API keys (test and live), Stripe Tax with the OSS registration,
  customer portal settings, webhook endpoints, Stripe's review of the business.
- DEVELOPMENT.md.
