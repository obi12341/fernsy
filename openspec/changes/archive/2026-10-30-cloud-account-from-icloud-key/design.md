# Design

## Context

See proposal.md – Why. This change builds on `add-recording-cloud` (same branch, not yet
archived); its design is the reference for the parts that stay.

What exists now:
- **Account key.** `CloudAccountKey` holds `id` (a UUID string) and `raw` (256 random bits).
  It is stored in the keychain and in the CloudKit record `cloud.key` (type `CloudKey`,
  `encryptedValues["key"]`) in the container `iCloud.de.mobilistics.fernsy`.
  `CloudKeyStore.createIfMissing` saves with `ifServerRecordUnchanged`, so racing creators end
  with one key. Today only the Mac calls it (add-recording-cloud design A).
- **Server identity.** Sign in with Apple: `POST /v1/session` turns an identity token into an
  HS256 session token. `users.apple_sub` holds Apple's user id. The subscription is linked by
  the original transaction id that the app sends after sign-in, first claim wins
  (add-recording-cloud design F and G).
- **Production.** `fernsy-cloud` was deployed on 2026-10-30 with the App Store Server API key.
  The App Store Server API answers 401 on production until the app has an approved in-app
  purchase. The worker then asks the sandbox (add-recording-cloud design F, as built).
- **Data.** Each D1 database holds only test accounts: the dev user and the user's sandbox
  account. The R2 buckets hold only test recordings and the UI-test fixture.

## Goals / Non-Goals

**Goals:**
- No identity prompt. The only dialog on the way in is Apple's purchase sheet.
- A transaction id alone never links a subscription to an account.
- The server never learns the encryption key. Its database cannot reveal the access secret.

**Non-Goals:**
- Protecting an account against someone who holds the user's unlocked device or iCloud
  data. Whoever has the key already has the recordings.
- Keeping the 2026-10-30 test accounts and recordings.

## Decisions

### A. Account id and access secret derived from the key

- **Account id:** the key's existing `id`, as a lowercased UUID. A UUID is what StoreKit
  accepts as `appAccountToken` (decision C).
- **Access secret:** `HKDF-SHA256(ikm: raw, salt: "fernsy-cloud-account-v1", info: id)`,
  32 bytes, derived with CryptoKit's `HKDF` on every device.
- **On the server:** it stores `auth_hash = SHA-256(secret)`. A plain hash is enough, since
  the secret has 256 bits of entropy and cannot be brute-forced; no slow password hash is
  needed.
- **Header:** every request sends `Authorization: Key <accountId>:<base64url(secret)>`, over
  TLS only.

The key from 2026-10-30 already has this shape, so existing keys keep working without a
migration.

Rejected:
- **Sending the raw key or a hash of it as the credential**: the server would hold, or be
  one step from, the encryption key. HKDF with its own salt separates the two.
- **A second random secret in its own CloudKit record**: one more record to sync and race
  over. Deriving it from the one key gives the same result.
- **HMAC-signed requests with a timestamp**: protects against replay, which TLS already
  covers, at the cost of clock handling on the Apple TV and more code on both sides.
- **The CloudKit user record id**: the worker cannot verify it (add-recording-cloud design
  G). The access secret, unlike it, is unguessable.
- **Keeping Sign in with Apple**: the double prompt and the missing purchase on the Apple TV
  are the reason for this change.

### B. Registration on first use

The first authenticated request with an unknown account id registers it. The server creates
the row with a random internal `id` (still the object prefix `u/<id>/`), the `account_id`
and the `auth_hash`. A known account id with a different hash gets 401.

Devices register when they create or first read the key, which happens before any purchase.
So the account id has not left the device before it is registered.

Rejected: an explicit `POST /v1/accounts`. It costs one more round trip and gives the same
security, since the first presenter wins either way.

### C. Purchase bound with `appAccountToken`

The purchase runs in this order:
1. Get the key, creating it if none exists on this Apple ID (decision D).
2. Call `GET /v1/account`, which registers the account.
3. Call `Product.purchase(options: [.appAccountToken(UUID(accountId))])`.
4. Send `POST /v1/subscription {originalTransactionId}`.

The server fetches the status from Apple, as before. It then compares the latest
transaction's `appAccountToken` with the requesting account:
- **Equal:** linked.
- **Missing or another account:** `409 other_account`. The app then offers "Move the
  subscription to this device" (decision E).

Restore works the same way: `AppStore.sync()`, then `currentEntitlements`, then
`POST /v1/subscription`.

D1 gets a `subscriptions` table:

| Column | Meaning |
|---|---|
| `original_transaction_id` | primary key |
| `token_account_id` | `appAccountToken` from Apple; null if the purchase has none |
| `user_id` | the user it is linked to now |
| `product_id`, `expires_at`, `revoked_at` | from Apple |

A user's state comes from the subscription linked to it. A user that loses its link gets
`ended_at = now`, which starts the existing 30-day grace period. Notifications and the cron
refresh subscriptions by transaction id, as before.

As built: StoreKit sits behind a small `CloudStore` protocol (`AppStoreCloudStore` in the
apps). `SKTestSession` cannot be used in `swift test`, because StoreKit answers `invalidApp`
without an app host, and the project has no hosted unit-test target. The model is tested with
a fake store, and the real purchase on devices (task 5.4).

Pitfall found in task 5.4: every transaction has to be finished, including the renewals that
arrive through `Transaction.updates` and the leftovers in `Transaction.unfinished`. The first
version finished only its own purchase. After an hour of sandbox renewals on the Mac,
`Product.purchase` returned one old, expired renewal per tap instead of showing the sheet,
and "Subscribe" seemed to do nothing. Now the app finishes transactions at launch, in the
updates listener and before a purchase. A purchase that leaves no active subscription shows
"The App Store did not confirm the subscription".

Rejected:
- **Linking by transaction id, first claim wins (the old rule)**: anyone who learns the id
  could claim the subscription.
- **Verifying the JWS chain**: still rejected for the reason in add-recording-cloud design F.
  The token check through Apple's API binds the purchase without it.

### D. Every device may create the key; locked means unreadable

`createIfMissing` is called on any device, but only when the user subscribes or restores,
never when a screen merely opens. The meaning of "locked" narrows:
- **Locked:** the `cloud.key` record exists but cannot be fetched, or iCloud is unavailable.
  Then the device shows the locked state and never creates a key.
- **Absent:** CloudKit answers `unknownItem` for the record. Only then may the device create
  one.

Any other CloudKit error counts as locked and is retried later. If an error were taken for
"absent", the device would make a second key and leave every upload unreadable.

Rejected: keeping key creation on the Mac only. The Apple TV could not subscribe on its own,
which is one of the two problems this change solves.

### E. Moving and taking back a subscription

**Move.** `POST /v1/subscription {originalTransactionId, move: true}` links the subscription
to the requesting account even when the token is missing or names another account. The old
user gets `ended_at = now` (grace). The app offers the move only after a `409 other_account`
for a subscription that the device's own StoreKit reports as active.

**Take-back.** On every authenticated request the server checks one indexed D1 lookup: is
there a subscription whose `token_account_id` is this account but whose `user_id` is not
this account's user? If so, it relinks the subscription, and the other user gets
`ended_at = now`. The account the purchase was made for therefore always wins in the end. A
move made by someone who only learned the transaction id lasts only until the buyer's next
request.

Rejected: no move at all. A user who lost their iCloud data would keep paying for a
subscription they could not use until it expires, and Apple support would have to refund it.

### F. Mac marker in CloudKit

The Mac writes the record `cloud.mac` (type `CloudMac`, plain field `seenAt: Date`). It
writes it at launch when Fernsy Cloud is enabled in the build, and not more than once a day.
iPad, iPhone and Apple TV fetch it before showing the offer:
- **Found:** offer subscribe and restore.
- **`unknownItem`:** show the note that Fernsy on a Mac with the same Apple ID records.
- **Other error:** show the iCloud note. Without iCloud there is no key anyway.

A device that already has an active subscription skips the check, so existing subscribers
always see their recordings.

Rejected:
- **The iCloud key-value store**: it syncs eventually, so a fresh Apple TV can read an empty
  store and wrongly say "no Mac". A direct CloudKit fetch answers from the server.
- **Inferring a Mac from the key**: after decision D, any device can make the key.
- **A server-side flag**: the server would learn which kinds of devices a user has, and an
  account would be needed before the purchase screen.

### G. Deleting an account

`DELETE /v1/account`:
1. Aborts open uploads.
2. Deletes all objects under `u/<id>/` and the recording rows.
3. Deletes the user row.
4. Keeps the subscription row with `user_id = null`.

The next request with the same key registers a fresh user (decision B). The take-back rule
(decision E) then relinks the subscription by its token, so "Using it again" needs no extra
code. The apps say that cancelling is done in the App Store and link to
`showManageSubscriptions`, which exists on iOS and macOS. tvOS has no such sheet, so the
Apple TV names the Settings path instead.

### H. Removing Sign in with Apple

What goes away:
- **Server:** `/v1/session`, the HS256 sessions and their renewal header, `SESSION_KEY`,
  the identity-token check in `apple.js` and `users.apple_sub`.
- **Apps:** `AuthenticationServices` code, `CloudSignInButton`, the Mac's
  `SignInWithAppleButton`, the sign-out button, the session in the keychain, and the
  `com.apple.developer.applesignin` entitlement in all three entitlement files.
- **Strings:** the sign-in strings, unused from then on, are removed from the catalogs.

The development token (`Authorization: Dev …`, `IPTV_CLOUDTOKEN`) stays as it is. The
`APPLE_AUDIENCES` setting stays under the name `BUNDLE_IDS`, because the subscription check
still compares the transaction's bundle id.

## Risks / Trade-offs

- **[Account id squatting]** Someone who learns an account id before the device registers
  it could register it with their own secret, and the real device would get 401. → Devices
  register before the id ever leaves them (decision B). On a 401 for a known key, the app
  reports "account conflict" and support can reset the row.
- **[Move by a stranger]** Someone who knows a transaction id can move a subscription for a
  moment. → The buyer's account takes it back on its next request (decision E). Their
  recordings stay, since grace runs 30 days. A purchase without a token, possible after
  resubscribing outside the app, has no take-back. → After every purchase and restore, the
  app makes sure a token-bearing transaction exists. Apple keeps the token on renewals.
- **[Key lost means a new account]** Recordings under the old key become unreadable, as
  before. → The move keeps the purchase. The old recordings are deleted after grace.
- **[Leaked access secret]** It equals access to the account, but not to content, because
  the content needs the raw key. → It is derived anew on each device, never stored
  separately, and never logged.
- **[The Mac marker is missing on a Mac that never had cloud enabled in its build]** →
  Builds with `FERNSY_CLOUD = YES` write it at launch. Before launch only test builds exist.
- **[App Review]** No account creation UI. An implicit account still gets "Delete Fernsy
  Cloud data", which satisfies the account-deletion rule.

## Migration Plan

1. Server: create the new schema (`users` with `account_id`/`auth_hash`, plus
   `subscriptions`) by dropping and recreating the tables on `fernsy-cloud-dev` and
   `fernsy-cloud`. Delete the `u/` objects in both buckets. Deploy without `SESSION_KEY`.
2. CloudKit: create the record type `CloudMac` (field `seenAt`, Date/Time) in Development of
   `iCloud.de.mobilistics.fernsy` and deploy it to Production, as was done for `CloudKey`
   (DEVELOPMENT.md).
3. Sandbox: the tester's existing subscription has no token. Clear the tester's purchase
   history in App Store Connect (Users and Access › Sandbox › the tester › Clear Purchase
   History), or move it once with the new flow.
4. Re-upload the UI-test fixture to the dev server (DEVELOPMENT.md › Fernsy Cloud).
5. Rollback: none needed before launch. The feature stays behind `FERNSY_CLOUD`.
