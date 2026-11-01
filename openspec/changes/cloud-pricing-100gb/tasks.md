# Tasks

## 1. Worker

- [x] 1.1 `DEFAULT_QUOTA` 100 GB in `cloud-server/worker.js`; the allowance comment in `assistant.js` final; `cloud-server/README.md`; worker tests green (`node --test cloud-server/test/*.test.js`), with a test for an account above the quota (plays, deletes, upload refused with 0 free)
- [ ] 1.2 Deploy `fernsy-cloud-dev` and `fernsy-cloud`; `/v1/account` reports 100 GB. Dev deployed 2026-11-01 (100 GB); the prod deploy needs the user (blocked for the agent)

## 2. Prices

- [ ] 2.1 Paddle sandbox and live: 3.49 € monthly price on Fernsy Cloud (quantity 1..1; the live price `pri_01m6c4cd7tfteh5ybbjqcda4gj` exists since website-legal-pages, and `fernsy-cloud` sells it since 2026-11-01, `/v1/offer` €3.49; sandbox price `pri_01m6cgcw4wawgg2kxrz7xchzcj` on `fernsy-cloud-dev` since 2026-11-01, `/v1/offer` €3.49; open: archiving both 2.99 € prices, which the user approves), `PADDLE_PRICE_ID` on both workers, 2.99 € prices archived after asking the user; `/v1/offer` answers €3.49
- [x] 2.2 `Config/FernsyCloud.storekit` at 3.49; test fixtures that name the price follow
- [ ] 2.3 App Store Connect price 3.49 € for `de.mobilistics.fernsy.cloud.monthly`, existing subscribers keep theirs (user)

## 3. Verification

- [x] 3.1 Mac and iOS show "of 100 GB" against the dev worker; the DMG's offer reads 3,49 €; `openspec validate --all --strict`. iOS: `testPaddleSubscriptionIsManagedWhereBought` checks "of 100 GB used" against the dev worker; the Mac shows the same `CloudModel.storageText`; the DMG's offer is `/v1/offer`, €3.49 on dev

## Workflow follow-up

- Release-note trailers on the commit users notice; archive, merge into `main` and push.
