# Tasks

## 1. Stripe account (user, with my help)

- [x] 1.1 Stripe test and live API keys for the worker and the page (secret or restricted key, publishable) in `~/.config/fernsy/` (mode 600); Stripe Tax on with the OSS registration; customer portal (cancel at period end, payment method update, invoices); Smart Retries and Stripe's customer e-mails (receipts, failed payments, cancellation) on. The Stripe MCP (plugin `stripe`, sandbox `acct_1UX6aYEsDUkIy6j0`) sets up catalog and settings in test mode
- [x] 1.2 Test mode: product "Fernsy Cloud", price 3.49 € monthly tax-inclusive; webhook endpoint for `fernsy-cloud-dev` (product `prod_VYDIKlaXjqTakI`, price `price_1UX6sEEsDUkIy6j0pSNBVVbY` with tax code `txcd_10103000`, portal `bpc_1UX6sOEsDUkIy6j0KWLUyzSf` with login page, endpoint `we_1UX6sUEsDUkIy6j02GfKsBMF` on API `2025-06-30.basil`; values in `~/.config/fernsy/stripe-test.json`)

## 2. Worker

- [x] 2.1 `stripe.js`: signature check, subscription mapping, API calls (customer, subscription, portal session, cancel at period end, price text) with a pinned API version; tests with recorded test-mode payloads and forged signatures
- [x] 2.2 Routes: `GET /v1/offer`, `POST /v1/checkout`, `POST /v1/checkout/verify`, `POST /v1/checkout/subscribe`, `POST /v1/stripe/notifications`, `POST /v1/subscription/portal`; provider `stripe`; refresh from Stripe when the period ended; Paddle code and tests removed
- [x] 2.3 `deploy.sh` and README: Stripe secrets, Paddle secrets dropped; dev deploy

## 3. Website

- [x] 3.1 `cloud.html` / `en/cloud.html`: order summary, Payment and Address Element, start request, "Zahlungspflichtig abonnieren" / "Subscribe and pay", links to terms, refunds, withdrawal
- [x] 3.2 Withdrawal pages (`widerruf.html`, `en/withdrawal.html`) with the model form; footers. The cancellation page was built and removed again by the user's decision (design 4)
- [x] 3.3 Terms, pricing, refunds and privacy pages: mobilistics as seller, Stripe as processor, Stripe.js on the checkout page

## 4. Apps

- [x] 4.1 FernsyCore `WebCloudStore`, `Account.isWebPurchase`, failures renamed; `CloudModelTests`
- [x] 4.2 Mac DMG texts and German strings without Paddle; iOS/TV note on `isWebPurchase`; App Store app binaries contain no Stripe or checkout strings (the DMG's two hints are verbatim texts in `#if DIRECT_DISTRIBUTION`, not in the string catalog; checked in the built App Store Mac app)

## 5. Verification and go-live

- [x] 5.1 Test mode end to end: DMG subscribes with a Stripe test card through the local checkout page → active within a minute on the Mac and in the iOS simulator; portal; second purchase refused; `openspec validate --all --strict`
- [ ] 5.2 Live: Stripe's go-ahead, live price and webhook, prod deploy, pricing page matches; DEVELOPMENT.md. Done 2026-11-01 through the MCP in the live account
  `acct_1UX6aEEWpaD5hstl`: product `prod_VYDveudH47ZSGT`, price `price_1UX7TREWpaD5hstlnXH8eMXl` (3.49 €,
  inclusive), portal `bpc_1UX7TeEWpaD5hstlNSRhmW8I` (not the account's default, so the worker passes
  `STRIPE_PORTAL_CONFIG`), webhook `we_1UX7TeEWpaD5hstl25x6lT8e` for `fernsy-cloud` (values in
  `~/.config/fernsy/stripe-live.json`); tax settings were already active (head office Dortmund). Payment method domains `www.fernsy.app` and `fernsy.app`
  registered live (Apple Pay and Google Pay active; no association file needed with Stripe).
  The user then added the DE registration (small seller, live and sandbox), Stripe Tax Basic,
  payment methods card, Apple Pay, Google Pay only (domains registered), customer and billing
  e-mails, Smart Retries (cancel after the last retry, cancel at once on a dispute), public
  details, and the restricted live key (customers, subscriptions, customer portal write;
  invoices, payment intents, prices, products read; balance and charges refused). Prod worker
  deployed by the user from `e588dec` (`/v1/offer` €3.49, unsigned webhook 400, Paddle secrets
  dropped). Open: a live purchase with refund after the website is merged; rotating the sandbox key

Test mode end to end, 2026-11-01: the DMG (Debug, `IPTV_TESTCLOUDBUY`, `IPTV_CHECKOUTPAGE`) opened the
local checkout page; without the start request the page refuses, with it Stripe's test card paid
the first invoice (3.49 €, Stripe Tax `not_collecting` until the sandbox has a tax registration)
and the Mac saw the subscription after 42 s and switched uploads on. The account reads `provider:
stripe`, 100 GB; the portal link opens Stripe's portal; a second checkout is refused. A
cancellation page (by e-mail address) worked in the test and was then removed by the user's
decision (design 4). The iOS UI test `testWebSubscriptionIsManagedWhereBought` passes with the same
key; Mac (both variants) and Apple TV build.

## Workflow follow-up

- Release-note trailers on the DMG commit users notice; archive, merge into `main` and push.
