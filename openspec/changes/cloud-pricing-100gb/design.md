# Design

## Context

See proposal.md › Why. The quota is the worker constant `DEFAULT_QUOTA` (overridable with
`QUOTA_BYTES`, per account with `users.quota_bytes`), the assistant allowance the worker setting
`ASSISTANT_MONTHLY` (default 300). The apps never hard-code price or quota: StoreKit or
`/v1/offer` name the price, `/v1/account` the storage.

Costs per subscriber and month, measured or quoted on 2026-11-01:

| Item | Cost |
|---|---|
| R2 storage | about 0.014 € per GB (0.015 $), operations and egress negligible |
| Assistant request (Haiku 5.5 via OpenRouter) | about 0.0016 € (dev sample: 3.6 rounds, 13.6k input and 460 output tokens per request) |
| 100 GB full and 300 requests | 1.84 € |
| 250 GB full and 300 requests | 3.91 € |

Net per month after 19 % VAT: at 2.99 € 2.14 € (Apple, 15 %) and 1.90 € (Paddle, 5 % + 0.50 $);
at 3.49 € 2.49 € and 2.30 €. Fixed costs (Workers Paid, Apple Developer Program) are about 12 €
a month.

## Goals / Non-Goals

**Goals:** no subscriber costs more than they bring, even at full use; one price in both stores.

**Non-Goals:** usage-based billing, a storage add-on, changing the assistant model.

## Decisions

### 1. 3.49 € a month with 100 GB
Full use leaves about 0.45–0.65 € a month, typical use (around 75 GB, 100 requests) about
1.10–1.30 €.
Rejected: 2.99 € with 100 GB (full use leaves 0.06 € through Paddle); 250 GB at any price under
5 € (full use is a loss); a second plan with 300 GB at 6.99 € and a yearly plan at 34.99 €
(the user chose one monthly plan for now; the yearly plan would halve Paddle's fixed fee and can
come later).

### 2. 300 assistant requests stay
At 0.0016 € each the full allowance costs 0.46 €; the limit guards against scripted abuse rather
than normal use.
Rejected: fewer requests (saves cents, feels stingy); a larger model by default (Sonnet 5.5 costs
about 20 times as much per request).

### 3. Over-quota accounts keep their recordings
The quota is enforced when an upload starts, as today; nothing is deleted when the quota shrinks.
Rejected: deleting the oldest recordings above 100 GB (destroys data the user paid to keep).

### 4. Existing subscribers
App Store Connect: the new price for new subscribers, existing ones keep their price ("preserve
current price"), so nobody has to confirm an increase. Paddle: a new price on the same product;
existing subscriptions keep the old price, the old price is archived. The quota applies to every
account.
Rejected: raising existing subscribers (Apple asks some of them to agree, and there are hardly
any yet).

## Risks / Trade-offs

- [The token sample is small (14 requests on the dev worker)] → The relay logs tokens per round;
  recheck after a month of real use, before the allowance or model changes.
- [Paddle's 0.50 $ per payment weighs on a small monthly price] → A yearly plan is the lever if
  Paddle's share proves too large.

## Migration Plan

1. Worker: `DEFAULT_QUOTA = 100 GB`, deploy dev, then prod.
2. Paddle sandbox and live: a 3.49 € monthly price (quantity 1..1) on Fernsy Cloud, set it as
   `PADDLE_PRICE_ID`, archive the 2.99 € price.
3. App Store Connect (user): 3.49 € for `de.mobilistics.fernsy.cloud.monthly`, existing
   subscribers keep their price.
4. Rollback: the quota is a constant and the price a setting; both can return to the old values
   without an app update.
