# Tasks

## 1. Worker

- [ ] 1.1 `DEFAULT_QUOTA` 100 GB in `cloud-server/worker.js`; the allowance comment in `assistant.js` final; `cloud-server/README.md`; worker tests green (`node --test cloud-server/test/*.test.js`), with a test for an account above the quota (plays, deletes, upload refused with 0 free)
- [ ] 1.2 Deploy `fernsy-cloud-dev` and `fernsy-cloud`; `/v1/account` reports 100 GB

## 2. Prices

- [ ] 2.1 Paddle sandbox and live: 3.49 € monthly price on Fernsy Cloud (quantity 1..1), `PADDLE_PRICE_ID` on both workers, 2.99 € prices archived; `/v1/offer` answers €3.49
- [ ] 2.2 `Config/FernsyCloud.storekit` at 3.49; test fixtures that name the price follow
- [ ] 2.3 App Store Connect price 3.49 € for `de.mobilistics.fernsy.cloud.monthly`, existing subscribers keep theirs (user)

## 3. Verification

- [ ] 3.1 Mac and iOS show "of 100 GB" against the dev worker; the DMG's offer reads 3,49 €; `openspec validate --all --strict`

## Workflow follow-up

- Release-note trailers on the commit users notice; archive, merge into `main` and push.
