# Proposal

## Why

The first real-device run of Fernsy Cloud (add-recording-cloud, 2026-10-30) worked, but the
way in loses customers. The user confirms the purchase, then has to "Sign in with Apple"
again on every device. The Apple TV cannot subscribe at all, only restore. All of the user's
devices already share one secret without any prompt: the cloud key in their end-to-end
encrypted iCloud data. If the Fernsy Cloud account comes from that key, the only dialog left
is Apple's own purchase confirmation, on any device.

## What Changes

- **The account comes from the cloud key.**
  - The account id and an access secret are derived from the iCloud key on the device. The
    server stores only a hash of the access secret.
  - Every device that has the key is signed in, without any prompt. Nobody types or confirms
    anything.
  - The encryption key itself still never leaves the user's devices.
- **The purchase is bound to the account.** It carries the account id as StoreKit's
  `appAccountToken`. The server links a subscription only to the account whose id Apple
  reports for that transaction, so knowing a transaction id is no longer enough to claim it.
- **Subscribe on every device, including the Apple TV.**
  - Any device may create the key when none exists yet. The existing race-safe save keeps
    one key.
  - On iPad, iPhone and Apple TV the offer appears only when a Mac with Fernsy is known in
    the user's iCloud, since only the Mac records. Otherwise they explain that a Mac is
    needed.
- **Moving the subscription.** If the key is lost and a new one is created, a device whose
  App Store account owns the subscription can move it to the new account. The account the
  purchase was made for can always take it back.
- **Deleting cloud data.** Settings get "Delete Fernsy Cloud data", which removes all
  recordings and the account on the server. The subscription itself is managed in the App
  Store.
- **BREAKING (pre-launch only)**:
  - Sign in with Apple is removed: buttons, entitlement, server sessions and identity-token
    checks.
  - The server's database is reset on both deployments. Only the test accounts of
    2026-10-30 exist there.

Out of scope:
- Recording or uploading anywhere other than the Mac. The Mac marker only gates the offer.
- Family Sharing for the subscription.
- Recovering recordings after the key is lost. Moving the subscription keeps the purchase,
  not the old recordings.
- Verifying the JWS certificate chain in the worker (still rejected, add-recording-cloud
  design F).
- The App Store launch itself: pricing, review, privacy text, legal review.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
These two capabilities are introduced by the unarchived change `add-recording-cloud` on the
same branch. This change is archived right after it, so its deltas apply on top.
- `recording-cloud`:
  - the key may be created on any device;
  - the switch, the subscription and first use need no sign-in;
  - purchase on every device, offered on iPad, iPhone and Apple TV only when a Mac is known;
  - moving the subscription;
  - deleting all cloud data.
- `cloud-server`:
  - accounts identified by the derived account id and access secret instead of Sign in with
    Apple;
  - subscription linking by `appAccountToken`, with move and take-back;
  - deleting an account;
  - the development token wording.

## Impact

- **Server** (`cloud-server/`): new account and auth path, subscription linking by token,
  `DELETE /v1/account`. `/v1/session`, session tokens and the identity-token code go away.
  New D1 schema, and both deployments get a fresh database.
- **FernsyCore**:
  - `CloudCrypto` gets the HKDF derivation.
  - `CloudKeyStore` lets every device create the key and gets the Mac marker record.
  - `CloudClient` gets the key credential instead of sessions.
  - `CloudModel` gets purchase with `appAccountToken`, move and delete, and loses sign-in.
- **Apps**:
  - Mac, iOS and tvOS settings and recordings screens lose the sign-in step and get
    purchase, the no-Mac note and delete.
  - `FernsyTV/Design/CloudSignInButton.swift` goes away.
- **Entitlements**: `com.apple.developer.applesignin` is removed from all three apps.
- **CloudKit**: a new record type `CloudMac` has to be created in the release container and
  deployed to Production, like `CloudKey` (DEVELOPMENT.md).
- **Strings**: sign-in strings go away; new English and German strings.
