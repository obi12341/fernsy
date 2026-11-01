# Proposal

## Why

Fernsy Cloud launched with placeholder numbers: 2.99 € a month, 250 GB per account and a
"provisional until pricing" assistant allowance. A subscriber who fills 250 GB costs about
3.90 € a month in storage and assistant tokens, while 2.99 € leaves 2.14 € (App Store) or 1.90 €
(Paddle) after VAT and fees, so every heavy user is a loss. The numbers have to be set before
the first real subscribers arrive.

## What Changes

- One plan, monthly only: **3.49 € a month** (was 2.99 €), the same in the App Store and in
  Paddle's checkout.
- **100 GB** of cloud storage per subscription (was 250 GB).
- **300 assistant requests a month**, now final rather than provisional (the number itself stays).
- An account that already stores more than 100 GB keeps playing, downloading and deleting its
  recordings; new uploads are refused until it is below the quota again.
- The local StoreKit configuration, the Paddle catalog (sandbox and live) and the
  documentation carry the new price; App Store Connect's price is set by hand.

Out of scope: further plans or a larger tier, a yearly subscription, regional price tuning
beyond what Apple and Paddle derive from the euro price, and the legal texts (terms, refund
policy, the privacy page naming Paddle), which follow separately.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recording-cloud`: the Quota requirement names 100 GB per subscription and how an account
  above it behaves.
- `assistant`: the allowance requirement names 300 requests a month.

## Impact

- `cloud-server/worker.js` (`DEFAULT_QUOTA`), `cloud-server/assistant.js` (comment on the
  allowance), `cloud-server/README.md`.
- `Config/FernsyCloud.storekit` (local purchase tests).
- Paddle: a new 3.49 € price on the Fernsy Cloud product in the sandbox and live, the worker's
  `PADDLE_PRICE_ID` on `fernsy-cloud-dev` and `fernsy-cloud`; the 2.99 € prices are archived.
- App Store Connect: the price of `de.mobilistics.fernsy.cloud.monthly` (user).
- No app code shows a fixed price or quota: the offer comes from StoreKit or `/v1/offer`, the
  quota from `/v1/account`.
