# Tasks

## 1. Server: accounts from the key

- [x] 1.1 `schema.sql` and `store.js`:
  - `users(id, account_id UNIQUE, auth_hash, created_at, ended_at, quota_bytes)`;
  - `subscriptions(original_transaction_id PK, token_account_id, user_id, product_id, expires_at, revoked_at)` with an index on `token_account_id`;
  - user state from the linked subscription;
  - `ended_at` set when a user loses its link.

  Verify with `node --test cloud-server/test` on the SQLite stand-in: the grace and deletion queries still pass on the new tables.
- [x] 1.2 `worker.js` authentication (design A, B):
  - `Authorization: Key <accountId>:<secret>`; an unknown UUID registers with `SHA-256(secret)`;
  - a known id with another hash answers 401;
  - the dev token path stays;
  - `/v1/session`, sessions, `SESSION_KEY` and the identity-token code in `apple.js` are removed.

  Verify with route tests: first request registers, wrong secret 401, a non-UUID id 401, the dev token works, and no secret text appears in captured logs.
- [x] 1.3 Subscription linking (design C, E): `POST /v1/subscription` compares Apple's `appAccountToken` with the account and answers `409 other_account` on a missing or foreign token. `move: true` links anyway and ends the old user's link. The take-back check runs on every authenticated request. Notifications and cron refresh by transaction id. Verify with route tests using recorded Apple answers:
  - matching token links;
  - a foreign token gets 409 and the other link stays;
  - a move followed by a request of the token's account takes it back, and the mover enters grace;
  - a transaction id alone never links.
- [x] 1.4 `DELETE /v1/account` (design G): aborts uploads, deletes `u/<id>/` objects and rows, keeps the subscription with `user_id` null. The next request re-registers and takes the subscription back. Verify with a route test, then on the dev worker with `IPTV_CLOUDTOKEN`: upload a small file, delete the account, and `GET /v1/recordings` is empty.
- [x] 1.5 Rename `APPLE_AUDIENCES` to `BUNDLE_IDS`. Update `cloud-server/README.md` (routes, header, secrets) and `deploy.sh` (no `SESSION_KEY`). Verify that `scripts/test.sh` passes and that the README's routes match `worker.js`.

## 2. FernsyCore

- [x] 2.1 `CloudAccountKey`: `accountId` (lowercased id) and `accessSecret` (HKDF-SHA256, salt `fernsy-cloud-account-v1`, info = id, 32 bytes). Verify with `CloudCryptoTests`: a fixed test vector, so that Swift and the worker's tests agree on the derivation; and the secret differs from the raw key.
- [x] 2.2 `CloudKeyStore` (design D, F):
  - `createIfMissing` may run on any device;
  - absent only on `unknownItem`, any other error is locked;
  - the `cloud.mac` marker is written (at most daily) and read.

  Verify with fake-backing tests: an error never creates a key; two creators race to one key; the marker is written once per day and read as found, absent or error.
- [x] 2.3 `CloudClient`: a `.key(accountId, secret)` credential replaces `.session`. Remove `signIn`, the renewal header and the keychain session. Add `deleteAccount()` and `linkSubscription(_:move:)` with the `otherAccount` failure. Verify with the `URLProtocol` stub tests (header format, 409 mapping) and the live dev-server test with `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`.
- [x] 2.4 `CloudModel`: purchase in the order of design C with `appAccountToken`; restore; the move offer after `otherAccount`; delete; the "Mac known" state from the marker. Sign-in and sign-out are removed. Verify with `FernsyCoreTests/CloudModelTests` against a fake `CloudStore` and a stubbed server:
  - opening creates no key;
  - the purchase registers the key first and carries its account id as token;
  - restore on a second device;
  - move after 409;
  - expiry and refund end the subscription;
  - delete empties the list.

  StoreKit itself refuses to run without an app host (`invalidApp` under `swift test`), so the real purchase is checked in 5.4. This replaces add-recording-cloud task 5.2.

## 3. Mac

- [x] 3.1 Settings › Recordings › Fernsy Cloud and the enable sheet: subscribe or restore, then the switch is on, with no sign-in step. Below it: state, storage, grace note, "Delete Fernsy Cloud data" with confirmation and "Manage subscription", the move offer, and the account-conflict message. Write the marker at launch. Remove `SignInWithAppleButton` and the sign-in strings, and add the new strings in English and German. Verify in a Debug run with `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`/`IPTV_CLOUDKEY=local`: screenshots of none, active, grace and the delete confirmation, and no sign-in UI anywhere.
- [x] 3.2 Remove `com.apple.developer.applesignin` from `Config/Fernsy.entitlements`, `FernsyiOS.entitlements` and `FernsyTV.entitlements`. Verify that the Debug and Release builds of all three targets sign, and that `codesign -d --entitlements -` shows no `applesignin`.

## 4. iPad, iPhone and Apple TV

- [x] 4.1 iOS `CloudSettingsView` and the Recordings tab:
  - with the marker: subscribe and restore;
  - without it: the note that a Mac is needed;
  - with a subscription: the account, delete, manage subscription, move offer;
  - no sign-in anywhere.

  Remove `CloudSignInButton`. Verify with `FernsyiOSUITests/CloudRecordingsUITests` (`IPTV_CLOUD`/`IPTV_CLOUDTOKEN`/`IPTV_CLOUDKEY`), plus a test for the no-Mac note using a debug override `IPTV_CLOUDMAC=0`.
- [x] 4.2 Apple TV `CloudSettingsScreen` and the Recordings shelf, as in 4.1. Subscribe works with the remote; there is no manage sheet on tvOS, so the Settings path is named instead. Verify with `FernsyTVUITests/CloudRecordingsUITests` on "Claude Apple TV" (`scripts/tv-uitest.sh`), including `IPTV_CLOUDMAC=0`.
- [x] 4.3 Document `IPTV_CLOUDMAC` and the new account model in DEVELOPMENT.md › Fernsy Cloud. Add the `CloudMac` record type to the CloudKit schema note. Verify that the documented commands run as written.

## 5. Deployment and integration

- [x] 5.1 Reset both D1 databases to the new schema and empty the `u/` prefix in both buckets. Deploy `fernsy-cloud-dev` and `fernsy-cloud`, then re-upload the UI-test fixture with `uploadUITestFixture`. Verify with `GET /v1/account` using a fresh test key on production: 200, state none.
- [x] 5.2 Ask the user to create `CloudMac` in CloudKit Development and deploy it to Production, and to clear the sandbox tester's purchase history. Verify that a Release Mac build writes `cloud.mac` without an error in its log.
- [x] 5.3 Run `openspec validate --all --strict`, `scripts/test.sh`, and the full Apple TV and iPad UI test runs. All must pass.
- [x] 5.4 Real devices with Release builds, `FERNSY_CLOUD = YES`, production worker and the sandbox tester. Install on the Mac, "iPad von Patrick" and "Apple TV WZ". Then: *Done 2026-10-30 by the user; the re-purchase on the Mac exposed the unfinished-transactions pitfall (design C, as built).*
  - subscribe on the Apple TV with only Apple's purchase sheet;
  - the Mac's switch turns on without buying or any prompt;
  - a recording uploads, and the iPad lists and plays it without any prompt;
  - "Delete Fernsy Cloud data" on the iPad empties every list.

  This replaces add-recording-cloud task 8.2. The user does it with their Apple ID.

## Workflow follow-up

- On `change/add-recording-cloud`: archive `add-recording-cloud` first, then this change, so the deltas apply in order. Then merge into `main` and push, with the user's consent.
- Mark add-recording-cloud tasks 5.2 and 8.2 as covered by 2.4 and 5.4 here before archiving it.
