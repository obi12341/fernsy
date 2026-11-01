# Tasks

## 1. Stripe account (user, with my help)

- [ ] 1.1 Stripe test and live API keys for the worker and the page (secret or restricted key, publishable) in `~/.config/fernsy/` (mode 600); Stripe Tax on with the OSS registration; customer portal (cancel at period end, payment method update, invoices); Smart Retries and Stripe's customer e-mails (receipts, failed payments, cancellation) on. The Stripe MCP (plugin `stripe`, sandbox `acct_1UX6aYEsDUkIy6j0`) sets up catalog and settings in test mode
- [ ] 1.2 Test mode: product "Fernsy Cloud", price 3.49 € monthly tax-inclusive; webhook endpoint for `fernsy-cloud-dev`

## 2. Worker

- [ ] 2.1 `stripe.js`: signature check, subscription mapping, API calls (customer, subscription, portal session, cancel at period end, price text) with a pinned API version; tests with recorded test-mode payloads and forged signatures
- [ ] 2.2 Routes: `GET /v1/offer`, `POST /v1/checkout`, `POST /v1/checkout/verify`, `POST /v1/checkout/subscribe`, `POST /v1/stripe/notifications`, `POST /v1/subscription/portal`, `POST /v1/subscription/cancel` (rate-limited); provider `stripe`; refresh from Stripe when the period ended; Paddle code and tests removed
- [ ] 2.3 `deploy.sh` and README: Stripe secrets, Paddle secrets dropped; dev deploy

## 3. Website

- [ ] 3.1 `cloud.html` / `en/cloud.html`: order summary, Payment and Address Element, start request, "Zahlungspflichtig abonnieren" / "Subscribe and pay", links to terms, refunds, withdrawal
- [ ] 3.2 Withdrawal pages (`widerruf.html`, `en/withdrawal.html`) with the model form; cancellation pages (`kuendigen.html`, `en/cancel.html`); footers
- [ ] 3.3 Terms, pricing, refunds and privacy pages: mobilistics as seller, Stripe as processor, Stripe.js on the checkout page

## 4. Apps

- [ ] 4.1 FernsyCore `WebCloudStore`, `Account.isWebPurchase`, failures renamed; `CloudModelTests`
- [ ] 4.2 Mac DMG texts and German strings without Paddle; iOS/TV note on `isWebPurchase`; App Store app binaries contain no Stripe or checkout strings

## 5. Verification and go-live

- [ ] 5.1 Test mode end to end: DMG subscribes with a Stripe test card through the local checkout page → active within a minute on the Mac and in the iOS simulator; portal; cancellation page; second purchase refused; `openspec validate --all --strict`
- [ ] 5.2 Live: Stripe's go-ahead, live price and webhook, prod deploy, pricing page matches; DEVELOPMENT.md

## Workflow follow-up

- Release-note trailers on the DMG commit users notice; archive, merge into `main` and push.
