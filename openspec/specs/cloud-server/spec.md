# cloud-server Specification

## Purpose
The Fernsy Cloud server: knows accounts by an access secret derived from the key in the user's
iCloud, checks their subscription, and lets their apps upload
and stream end-to-end encrypted recordings with short-lived signed URLs, while it never holds
keys or readable content.

## Requirements

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

### Requirement: Private storage per user
Each user's objects SHALL be stored under a location the server derives from the user id;
object ids SHALL be random. A user SHALL NOT be able to list, read, write or delete another
user's objects, and there SHALL be no public or shared access to any object.

#### Scenario: Another user's id
- **WHEN** a user asks for a streaming URL of a recording id that belongs to another user
- **THEN** the server answers not found

### Requirement: Signed upload URLs
For an active subscriber the server SHALL start an upload for a stated size when it fits the
free quota, and return signed URLs to upload the parts directly to storage, valid for at most
one hour, and renewable for an unfinished upload. Uploads SHALL be resumable part by part.

#### Scenario: Over quota
- **WHEN** an upload is started whose size exceeds the free quota
- **THEN** the server refuses it with the needed and the free bytes

#### Scenario: Larger than stated
- **WHEN** the completed upload is larger than the size stated at start and no longer fits the quota
- **THEN** the server deletes it and reports the upload as refused

### Requirement: Signed streaming URLs
For a user with an active subscription or within the 30-day grace period, the server SHALL
return a signed read URL for a recording's data and its encrypted details, valid for at most
six hours and usable with byte ranges.

#### Scenario: Seeking
- **WHEN** a player requests bytes from the middle of a recording with its signed URL
- **THEN** storage answers with exactly that range

### Requirement: Listing and deleting
The server SHALL list a user's completed recordings with id, size and upload time, report
used and total storage, and delete a recording on request, freeing its quota at once.
Unfinished uploads SHALL NOT be listed and SHALL be deleted after 7 days.

#### Scenario: Abandoned upload
- **WHEN** an upload was started 8 days ago and never completed
- **THEN** its parts are deleted and do not count against the quota

### Requirement: Deletion after subscription end
Thirty days after a user's subscription ended without renewal, the server SHALL delete all of
that user's objects and keep only the account row with its subscription state.

#### Scenario: Grace period over
- **WHEN** a subscription ended 31 days ago
- **THEN** all of that user's recordings are deleted and the user's used storage is zero

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
