# Spec Delta

## MODIFIED Requirements

### Requirement: Subscription check
The server SHALL decide whether a user's subscription is active only from Apple's App Store
Server API and Server Notifications, never from a client's claim alone. A subscription SHALL
be linked to the account whose id Apple reports as the transaction's app account token. A
transaction without that token, or with another account's, SHALL be linked only when the
request explicitly asks to move it.

#### Scenario: Renewal
- **WHEN** Apple notifies a renewal for a user's subscription
- **THEN** the user's subscription is active until the new expiry without the app doing anything

#### Scenario: Subscription of another account
- **WHEN** an account presents a transaction whose app account token names another account
- **THEN** the server refuses to link it and the other account's link stays

#### Scenario: Refund
- **WHEN** Apple notifies a refund
- **THEN** the subscription counts as ended from that moment

#### Scenario: Transaction id alone
- **WHEN** a request names a valid transaction id of someone else's purchase made for another account
- **THEN** the server does not link it to the requesting account

### Requirement: No keys or readable content
The server SHALL NOT receive, store or log encryption keys, access secrets, titles, channel
names or other readable recording details, and it SHALL NOT log signed URLs. Its logs SHALL
hold only account ids, recording ids, sizes, times and outcomes.

#### Scenario: Server logs
- **WHEN** a recording is uploaded, streamed and deleted
- **THEN** the server's logs for it contain only ids, sizes, times and outcomes

#### Scenario: Stored credentials
- **WHEN** the server's database is read
- **THEN** it holds only a hash of each account's access secret, from which the secret cannot be recovered

### Requirement: Development server
A separate development deployment SHALL exist that the app reaches through a debug switch and
that accepts a development token instead of a device key and a subscription, so uploads and
streaming can be tested automatically. The production deployment SHALL NOT accept it.

#### Scenario: UI test
- **WHEN** a UI test starts the app with the development server and token
- **THEN** it can upload, list, stream and delete without a key-derived account or purchase

## ADDED Requirements

### Requirement: Account from the device key
The server SHALL identify an account by an account id and an access secret that the apps
derive from the user's cloud key. It SHALL register an account id with the hash of its secret
on first use, and afterwards accept only requests that present that secret.

#### Scenario: First request of a new key
- **WHEN** a device presents an account id the server does not know, with an access secret
- **THEN** the server creates the account and stores only the hash of the secret

#### Scenario: Wrong secret
- **WHEN** a request presents a known account id with a different access secret
- **THEN** the server rejects it and the account stays unchanged

#### Scenario: Another device of the same user
- **WHEN** a second device with the same key presents the same account id and secret
- **THEN** it reaches the same account and recordings

### Requirement: Moving and taking back a subscription
The server SHALL move an active subscription to the requesting account when Apple confirms the
transaction and the request asks to move it. The account named by the transaction's app
account token SHALL get it back on its next request.

#### Scenario: Move
- **WHEN** an account asks to move a subscription whose token names an account that no longer has the key
- **THEN** the subscription counts for the requesting account, and the old account enters its 30-day grace period

#### Scenario: Take-back
- **WHEN** the account named by the token makes any request after its subscription was moved away
- **THEN** the subscription is linked to it again, and the other account enters its grace period

### Requirement: Deleting an account
The server SHALL delete all objects and the account row of the requesting account on request.
A later request with the same account id and secret SHALL start a new, empty account.

#### Scenario: Delete
- **WHEN** an account with three recordings asks to be deleted
- **THEN** the three recordings' objects are gone and the account no longer exists

## REMOVED Requirements

### Requirement: Sign-in with Apple
**Reason**: Sign in with Apple is replaced by the account id and access secret derived from the user's iCloud key, so no device asks for a sign-in.
**Migration**: Use "Account from the device key". Both deployments get a fresh database, since only test accounts existed before launch.
