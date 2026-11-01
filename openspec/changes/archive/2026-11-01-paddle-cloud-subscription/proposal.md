# Proposal

## Why

Fernsy Cloud (recordings cloud, assistant, Fernsy Server uploads) can only be bought through the
App Store, so people who use the DMG from the website cannot subscribe at all – StoreKit does not
work outside the App Store, although the DMG already has iCloud and CloudKit (Developer ID
profile) and thus the cloud key. A second way to pay, sold by Paddle as merchant of record,
opens Fernsy Cloud to them without taking on VAT, invoices and refunds ourselves.

## What Changes

- **Paddle subscription for the DMG**: the DMG's Fernsy Cloud settings offer "Subscribe" through
  a Paddle checkout on fernsy.app, opened in the browser with the account id; Paddle handles
  payment, VAT, invoices, refunds and the customer's billing portal.
- **Worker**: subscriptions from Paddle next to Apple's: a webhook endpoint (signature-checked)
  links a Paddle subscription to the account named in its custom data and keeps its state; the
  account's state is active when either provider's subscription is.
- **Manage and cancel**: "Manage Subscription" in the DMG opens an authenticated Paddle customer
  portal link minted by the worker; the worker stores only Paddle's customer and subscription
  ids, no e-mail address.
- **One subscription per account**: apps and checkout page do not offer a purchase while the
  account has an active subscription from either provider.
- The App Store builds stay as they are and never mention or link to the Paddle purchase
  (App Store Review Guideline 3.1.3(b): they may use a subscription bought elsewhere).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cloud-server`: subscriptions can come from Paddle as well as Apple.
- `recording-cloud`: the DMG sells the subscription through Paddle; the App Store apps keep the
  in-app purchase and accept a Paddle subscription of the same account.

## Impact

- `cloud-server/`: Paddle webhook route, subscription storage with a provider, portal-session
  route, secrets `PADDLE_API_KEY`, `PADDLE_WEBHOOK_SECRET` (sandbox for dev, live for prod).
- FernsyCore `CloudModel`/`CloudStore`: a Paddle store for `DIRECT_DISTRIBUTION` builds.
- Mac app (DMG target only): purchase and manage actions, strings in both languages.
- `website/`: checkout page in German and English (Paddle.js, sandbox and live client tokens),
  privacy pages (Paddle as seller and processor), terms and refund policy as Paddle requires.
- Paddle account: catalog (product, monthly price), notification destination, approved domain.

## Out of scope

- A Paddle purchase inside the App Store apps (iPhone, iPad, Apple TV, Mac App Store).
- Prices and discounts beyond one monthly price matching the App Store price (pricing is decided
  separately).
- Moving an existing Apple subscription to Paddle or back.
- Paddle's hosted mobile checkout (needs separate approval; the web checkout is enough).
