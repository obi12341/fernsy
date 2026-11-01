# Tasks

Against the dev worker (`IPTV_CLOUD=https://fernsy-cloud-dev.mobilistics.workers.dev`, dev token)
and the Paddle sandbox (test cards, webhook simulator); the DMG built with `scripts/build-dmg.sh`
or "Fernsy Direct" in Debug with `IPTV_CLOUD`.

## 1. Paddle account

- [ ] 1.1 Ask Paddle whether Fernsy Cloud fits its acceptable use policy (storage for one's own recordings and an assistant in an IPTV player that sells no content); record the answer in design.md – stop before the live tasks if it is no
- [x] 1.2 Sandbox catalog through the Paddle MCP: product "Fernsy Cloud" (tax category `saas`), one monthly price; notification destination for the dev worker; client-side token; verify with `products.list` and a simulated `subscription.created`

## 2. Worker

- [x] 2.1 `schema.sql`: `provider`, `customer_id`, `last_event_at` on `subscriptions`; `store.js` upserts for Paddle; existing tests stay green (`node --test cloud-server/test`)
- [x] 2.2 `paddle.js`: signature check, event mapping (created/updated/activated/canceled/past_due/paused), token verification; tests with recorded sandbox payloads and forged signatures
- [x] 2.3 Routes `POST /v1/checkout`, `POST /v1/checkout/verify`, `POST /v1/paddle/notifications`, `POST /v1/subscription/portal`; account JSON with `provider`; refresh from Paddle's API when older than a day; worker tests
- [x] 2.4 `deploy.sh`: `PADDLE_API_KEY`, `PADDLE_WEBHOOK_SECRET`, `PADDLE_CLIENT_TOKEN`, `PADDLE_PRICE_ID`, `PADDLE_ENV`; dev deploy with sandbox values; README routes

## 3. Website

- [x] 3.1 `website/cloud.html` and `website/en/cloud.html`: verify the token, show the price or "already subscribed", open Paddle.js overlay with `customData`, success note pointing back to the app; works without the app's token only as an explanation page
- [ ] 3.2 Terms, refund policy and privacy (Paddle as seller and processor) in both languages, as Paddle's domain review requires

## 4. Apps

- [x] 4.1 FernsyCore `PaddleCloudStore` and the provider in `CloudModel`; `CloudModelTests` with a fake store and a fake worker answer
- [x] 4.2 DMG (Fernsy Direct): Subscribe opens the checkout page, polling after return, "Manage Subscription" opens the portal link; strings in German and English; App Store targets unchanged (check the built App Store app for the absence of Paddle strings)
- [x] 4.3 App Store apps: "Manage Subscription" for a Paddle subscription shows the neutral note; no purchase offered while active

## 5. Verification and go-live

- [ ] 5.1 End to end in the sandbox: DMG subscribes with a test card → active within a minute on the Mac and in the iOS simulator with the same key; portal cancel → ends at period end; second purchase refused
- [ ] 5.2 Live: Paddle account verified, domain fernsy.app approved, live catalog (price with quantity 1..1) and secrets, default payment link `https://www.fernsy.app/cloud.html` (without it Paddle.js answers `transaction_default_checkout_url_not_set`), production deploy (after 1.1)
- [x] 5.3 DEVELOPMENT.md › Fernsy Cloud (Paddle part), `cloud-server/README.md`; `openspec validate --all --strict`

Sandbox purchase done 2026-11-01 through the checkout page in Chrome with Paddle's test card: the
real webhook made the dev account active (`provider: paddle`, period end a month later) and a second
checkout was refused. With the sandbox API key, `/v1/offer` gives €2.99 and the app's portal link
opens Paddle's portal. Cancelling there schedules the end at the period end, and the account stays
active until then. Cancelling at once through the API puts the account into grace (`endedAt` = the
cancel time, deletion 30 days later). Still open for 5.1: the DMG app itself through it, and the
iOS simulator with the same key.

## Workflow follow-up

- Release-note trailers on the DMG commits users notice; archive, merge into `main` and push
  with the user's consent; the DMG with the purchase ships with the next release.
