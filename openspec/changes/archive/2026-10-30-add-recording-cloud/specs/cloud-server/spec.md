# Spec Delta

## Purpose

The Fernsy Cloud server: signs users in, checks their subscription, and lets their apps upload
and stream end-to-end encrypted recordings with short-lived signed URLs, while it never holds
keys or readable content.

## ADDED Requirements

### Requirement: Sign-in with Apple
The server SHALL accept a Sign in with Apple identity token for the Fernsy apps, verify it
against Apple's keys, and answer with a session token. Every other request SHALL require a
valid session token; the user is identified only by Apple's stable user id.

#### Scenario: Forged token
- **WHEN** a request carries an identity token not signed by Apple or meant for another app
- **THEN** the server rejects it and creates no session

### Requirement: Subscription check
The server SHALL decide whether a user's subscription is active only from Apple's App Store
Server API and Server Notifications, never from a client's claim alone. A subscription SHALL
be linked to the first signed-in user who presents it; presenting it for another user SHALL
be refused.

#### Scenario: Renewal
- **WHEN** Apple notifies a renewal for a user's subscription
- **THEN** the user's subscription is active until the new expiry without the app doing anything

#### Scenario: Subscription of another account
- **WHEN** a user presents a transaction whose subscription is already linked to another user
- **THEN** the server refuses it and the other user's link stays

#### Scenario: Refund
- **WHEN** Apple notifies a refund
- **THEN** the subscription counts as ended from that moment

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
The server SHALL NOT receive, store or log encryption keys, titles, channel names or other
readable recording details, and it SHALL NOT log signed URLs. Its logs SHALL hold only user
ids, recording ids, sizes, times and outcomes.

#### Scenario: Server logs
- **WHEN** a recording is uploaded, streamed and deleted
- **THEN** the server's logs for it contain only ids, sizes, times and outcomes

### Requirement: Development server
A separate development deployment SHALL exist that the app reaches through a debug switch and
that accepts a development token instead of Sign in with Apple and a subscription, so uploads
and streaming can be tested automatically. The production deployment SHALL NOT accept it.

#### Scenario: UI test
- **WHEN** a UI test starts the app with the development server and token
- **THEN** it can upload, list, stream and delete without an Apple sign-in or purchase
