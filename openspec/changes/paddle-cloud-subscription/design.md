## Context

- The account is the cloud key: the apps derive `accountId` and an access secret from it
  (cloud-account-from-icloud-key); the worker keeps subscriptions in `subscriptions`
  (`original_transaction_id`, `token_account_id`, `user_id`, `expires_at`, `revoked_at`), filled
  from Apple only (`apple.js`, `/v1/apple/notifications`, `/v1/subscription`).
- The apps buy through FernsyCore's `CloudStore` protocol (`AppStoreCloudStore`, StoreKit 2,
  `appAccountToken` = accountId). The DMG is the "Fernsy Direct" target, compiled with
  `DIRECT_DISTRIBUTION`, signed with a Developer ID profile that carries iCloud/CloudKit, so it
  has the cloud key but no StoreKit purchases.
- Paddle (documentation checked 2026-11-01 through its docs MCP): merchant of record (VAT,
  invoices, refunds, chargebacks, billing support), checkout via Paddle.js on an approved domain,
  `customData` copied from the checkout's transaction to the subscription and every webhook,
  signed webhooks, customer portal sessions through the API, fees 5% + 50¢ per payment.

## Goals / Non-Goals

**Goals:** DMG users can subscribe and manage the subscription without an account of ours; one
account state for both providers; no e-mail or payment data on our side; App Store builds
untouched.

**Non-Goals:** see proposal (in-app Paddle purchase, pricing, provider moves).

## Decisions

### 1. Paddle as merchant of record
Paddle sells the subscription, so VAT/OSS, invoices, withdrawal rights and refunds are Paddle's.
Rejected: Stripe (lower fee, but we would be the seller: EU VAT by country through OSS, invoices,
terms and withdrawal handling ourselves); Lemon Squeezy (similar to Paddle, fewer tools here).

### 2. Checkout on fernsy.app, opened from the app with a signed token
The DMG asks the worker for a checkout token (`POST /v1/checkout`, authenticated with the access
secret): an HMAC over account id, environment and expiry (1 hour), not the access secret. It
opens `https://www.fernsy.app/cloud/?t=<token>` (`/en/cloud/` in English). The page sends the
token to the worker (`POST /v1/checkout/verify`), which answers whether the account may buy (no
active subscription) and which Paddle environment and price to use; the page then opens Paddle.js
overlay checkout with `customData: { fernsy_checkout: <token> }`. The webhook verifies that
token again before linking, so only an app of that account can start a purchase for it.
Rejected: the raw account id in the URL (anyone could attach purchases to any account id, and it
lands in browser history); Paddle's hosted checkout for Mac apps (needs a separate approval); an
in-app web view (Paddle advises against embedding; Apple Pay and password managers work better in
the browser).

### 3. Subscriptions with a provider
`subscriptions` gets `provider` (`apple` default, `paddle`) and `customer_id`; a Paddle
subscription's id (`sub_…`) goes into `original_transaction_id`, its current billing period end
into `expires_at`. `POST /v1/paddle/notifications` checks the `Paddle-Signature` header (HMAC-SHA256
of `ts:body` with the notification secret, at most 5 minutes old), handles
`subscription.created|updated|activated|canceled|past_due` (and ignores the rest with 200), and
keeps only newer events (`occurred_at` against the stored one). States: `active`/`trialing` →
active until the period end; `past_due` → active until the period end while Paddle retries;
`canceled` → ends at its `canceled_at`/scheduled end; `paused` → ended. The account is active
when any of its subscriptions is (existing query picks the latest `expires_at`).
Rejected: a separate `paddle_subscriptions` table (every state query would need two joins and the
grace and take-back logic twice).

### 4. Managing: Paddle's customer portal
`POST /v1/subscription/portal` (authenticated) creates a portal session for the account's Paddle
customer with its subscription id and returns the authenticated overview link; the DMG opens it
in the browser. Paddle's own e-mails carry portal links too. Rejected: building cancel/update
screens ourselves.

### 5. The DMG's store
FernsyCore gets `PaddleCloudStore: CloudStore`, used only in `DIRECT_DISTRIBUTION` builds:
`offer()` from the worker's verify answer (price text in the user's currency via Paddle's pricing
preview, made by the worker), `purchase` asks for the token and opens the browser (returns false:
the account becomes active through the webhook), `hasEntitlement`/`sync` read the account from
the worker. The Mac refreshes the account when it becomes active again (back from the browser)
and every 10 seconds for 5 minutes after opening the checkout. Account JSON gets `provider` so the
apps know what "Manage Subscription" opens (Apple's page or the portal link).
Rejected: a StoreKit-like local receipt (nothing local to verify; the worker is the source).

### 6. App Store builds
No Paddle code paths, strings or links outside `DIRECT_DISTRIBUTION`; the App Store apps simply
see the account as active (Guideline 3.1.3(b) multiplatform services; the subscription is also
offered as in-app purchase there). Their "Manage Subscription" for a Paddle subscription shows a
neutral note ("Manage it where you subscribed") instead of a link.

### 7. Environments
Dev worker ↔ Paddle sandbox (sandbox API key, notification secret and client token), production
worker ↔ Paddle live. The checkout page takes the environment from the token's verify answer, so
one page serves both.

## Risks / Trade-offs

- [Paddle's acceptable use review of an IPTV-related product] → ask Paddle before going live (task
  1.1); what is sold is storage for one's own recordings and an assistant, not content. Without
  approval the change stops before the live steps; nothing in the App Store builds depends on it.
- [Fees on a small monthly price: ~20% at 3 €] → accepted for reach; pricing decides separately
  (an annual price would lower the share).
- [Both providers active for one account] → apps and checkout page refuse a second purchase; if it
  happens anyway (race), the account stays active and the worker logs it; the user cancels one.
- [Webhooks lost or late] → Paddle retries; the Mac's polling and `GET /v1/account` refresh the
  subscription from Paddle's API when the stored state is older than a day.
- [Legal pages] → Paddle's domain review needs terms, refund policy and privacy on fernsy.app;
  the privacy pages name Paddle as seller and processor.

## Migration Plan

`schema.sql` adds the columns with defaults (`provider = 'apple'`), so existing rows stay valid.
Deploy dev with sandbox secrets, test end to end with Paddle's test cards, then live secrets,
domain approval and production deploy, then the DMG release. Rollback: hide the Subscribe action
in the DMG; existing Paddle subscriptions keep working through the webhooks.

## Open Questions

- The monthly price and whether to add an annual one (pricing, separate decision; the catalog
  task creates one monthly price matching the App Store price).
