# Design

## Context

`paddle-cloud-subscription` built the DMG's purchase around Paddle as merchant of record and
rejected Stripe because mobilistics would then be the seller (design 1 there). The new reason to
reopen it: Paddle's domain review refused fernsy.app as "Digital Content/Streaming Services"
(2026-11-01), and mobilistics already has a Stripe contract. What stays from that change: the
signed checkout token the DMG gets from `POST /v1/checkout` (HMAC over account, environment and
expiry), the checkout page on fernsy.app opened with it, the DMG polling the account after
opening the page, `provider` on subscriptions, and the neutral note in the App Store apps.

## Goals / Non-Goals

**Goals:** the DMG sells Fernsy Cloud through Stripe with mobilistics as seller, meeting the German
rules for online subscriptions (button text, withdrawal, cancellation button) as far as the site
can.

**Non-Goals:** our own invoices (Stripe's invoices/receipts with Stripe Tax serve), coupons,
several currencies beyond what Stripe shows from the euro price, the App Store purchase.

## Decisions

### 1. Stripe with mobilistics as seller
Stripe processes payments; VAT is calculated and shown by Stripe Tax (EU one-stop shop, which
mobilistics registers for), prices are tax-inclusive (3.49 € including VAT in every EU country).
Rejected: another merchant of record such as Lemon Squeezy or FastSpring (similar acceptable-use
rules, likely the same refusal, and a new contract); no web sale (DMG users would need the App
Store version or an iPhone to subscribe).

### 2. Our checkout page with Stripe's Payment Element
`cloud.html` keeps the token flow: it calls `POST /v1/checkout/verify` (the worker answers the
publishable key, price text and whether the account may buy), shows our order summary and the
Payment Element plus the Address Element in billing mode (country and postal code for Stripe
Tax), the start request and the button "Zahlungspflichtig abonnieren". On submit it calls
`POST /v1/checkout/subscribe` with the token, e-mail and the start consent; the worker creates
the customer and the subscription (`payment_behavior: default_incomplete`, `automatic_tax`,
metadata with the account id and the consent time) and returns the client secret, which the page
confirms with Stripe.js. The account is linked by the worker that created the subscription, not
by data from the page.
Rejected: Stripe Checkout (hosted): it labels the button "Abonnieren" for subscriptions, which
German law does not clearly accept as "zahlungspflichtig bestellen", and offers no field for the
start request; a payment link (no account binding, same button).

### 3. Webhooks and mapping
`POST /v1/stripe/notifications` checks `Stripe-Signature` (`t=…,v1=…`, HMAC-SHA256 of
`t.body` with the endpoint secret, at most 5 minutes old), handles
`customer.subscription.created|updated|deleted` and `invoice.paid`, and keeps only newer events
(`created`). States: `active`/`trialing` → active until the current period end; `past_due` →
active until the period end while Stripe retries; `incomplete` → not active; `canceled`,
`unpaid`, `incomplete_expired` → ended at `ended_at`/`canceled_at`. The subscription id (`sub_…`)
goes into `original_transaction_id`, the customer (`cus_…`) into `customer_id`, provider `stripe`.
The account is refreshed from Stripe's API when the stored period has ended, as with Paddle.
The Stripe API version is pinned in the requests.

### 4. Managing and cancelling
`POST /v1/subscription/portal` creates a billing portal session for the account's customer;
the DMG opens it. The cancellation page (`kuendigen.html`, `en/cancel.html`) sends the e-mail
address to `POST /v1/subscription/cancel`, which finds active Stripe subscriptions of customers
with that address and sets `cancel_at_period_end`; Stripe's subscription e-mails (cancellation
notice turned on in the Stripe settings) confirm it in text form. The answer never says more than
"cancelled until <date>" or "no subscription found", and the route is rate-limited per address and
IP. Rejected: a sign-in or an e-mail link first (the law asks for cancellation without further
hurdles); cancelling at once (the user paid for the month).

### 5. Withdrawal
Consumers may withdraw within 14 days. The checkout asks them to request the start before the
period ends and to acknowledge that they owe the share for the time used on withdrawal; the
worker stores the consent in the subscription's metadata. On withdrawal (by e-mail, the model
form, or the portal's cancellation within 14 days followed by a request) mobilistics refunds the
first payment minus the days used through Stripe's dashboard. Renewals are not refunded unless the
law requires it.
Rejected: "no refunds" (not allowed for consumers).

### 6. Apps
`PaddleCloudStore` becomes `WebCloudStore` (provider-neutral: offer, token, open page, poll,
portal); `Account.isPaddle` becomes `isWebPurchase` (`provider != "apple"`); the DMG's texts say
"You pay on fernsy.app with card, Apple Pay or other methods through Stripe." The App Store apps'
neutral note stays.

### 7. Environments
Dev worker ↔ Stripe test mode (test keys, test webhook endpoint, test price), prod worker ↔ live
mode. The checkout page takes the publishable key from the verify answer, so one page serves both.

## Risks / Trade-offs

- [Stripe's own review may also restrict IPTV-related businesses] → Present Fernsy Cloud as what it
  is (storage and an assistant, no content); test mode works regardless; live keys only after
  Stripe has no objection.
- [mobilistics carries VAT, invoices, chargebacks and support] → Stripe Tax, Stripe's receipts
  and dispute handling; volume is small.
- [The cancellation page can be used with someone else's address] → It only ends a subscription at
  the period end and says nothing about the address beyond the result; Stripe e-mails the owner,
  who can resume in the portal.
- [Legal texts drafted without a lawyer] → They follow the statutory model texts; the user has
  them reviewed before live.

## Migration Plan

1. Stripe test mode: product, tax-inclusive price, customer portal, webhook endpoint for the dev
   worker; dev deploy; end-to-end with test cards.
2. Remove Paddle secrets from both workers; keep `provider` values `apple`, `stripe`.
3. Live: Stripe Tax registrations, live price, portal, webhook endpoint, prod deploy.
4. Rollback: the DMG's purchase depends only on the worker's Stripe settings; without them the
   offer is hidden and the DMG shows where else to subscribe.
