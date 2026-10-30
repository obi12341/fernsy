# Proposal

## Why

Recordings are made on the Mac but cannot be watched on the iPad or the Apple TV. iCloud
Drive does not reach tvOS, and the Apple TV cannot record in the background. A private
recording storage that the user subscribes to lets the Mac upload a finished recording once,
and every Fernsy app can stream it, at home and away. The uploads must be end-to-end
encrypted, so that mobilistics as the operator can never see what is stored and does not
have to check content.

## What Changes

- New **Fernsy Cloud** service: a Cloudflare Worker (`cloud-server/`) with one R2 bucket and
  a D1 database. It signs users in with "Sign in with Apple", checks their App Store
  subscription, keeps a per-user quota, and hands out short-lived signed URLs for uploading
  and streaming. It only ever stores ciphertext under random ids.
- **End-to-end encryption** in the apps:
  - Every recording is encrypted on the Mac before upload, in fixed-size authenticated
    chunks, so a player can read any range.
  - The title, channel, times and gaps are encrypted as well.
  - The key never leaves the user's devices and their end-to-end encrypted iCloud storage.
- **Mac**: a global switch "Upload recordings to Fernsy Cloud". Turning it on needs the
  subscription and asks for Sign in with Apple once. While it is on, finished recordings
  upload automatically, and older ones can be uploaded per recording. It shows the upload progress and can resume an interrupted upload.
  Recordings that are only in the cloud are listed too.
- **iPad, iPhone and Apple TV**: a list of cloud recordings that stream directly, with
  seeking and without downloading first, and can be deleted.
- **Subscription**: an auto-renewable in-app subscription on all three apps. Without one,
  the cloud features show only what the subscription offers, and no app asks for a sign-in. When it ends, uploads stop, and
  stored recordings stay playable for a grace period before they are deleted.

Out of scope:
- Uploading while a recording runs, and watching it live from the cloud.
- Uploading from the Apple TV, and recording anywhere other than the Mac.
- Deleting the local file after upload.
- Sharing recordings with other users, family sharing, and web playback.
- Recovering recordings after the user has lost the key, for example after an iCloud data
  reset. This is the cost of end-to-end encryption.
- The App Store launch: prices, tiers, the App Review submission, the privacy policy text on
  the website, and the legal review of the service.
- A migration to another storage provider. The S3 interface keeps that open.

## Capabilities

### New Capabilities
- `recording-cloud`: In the apps, uploading recordings with end-to-end encryption, the key
  shared through iCloud, the subscription and Fernsy Cloud account, listing, streaming and
  deleting cloud recordings on Mac, iPad, iPhone and Apple TV.
- `cloud-server`: The Fernsy Cloud worker. Sign-in, subscription checks with Apple, quotas,
  signed upload and streaming URLs, deletion after a subscription ends, and the rule that it
  never holds keys or readable metadata.

### Modified Capabilities
- (none) The Mac's local recording behavior in `recordings` stays as it is. The cloud
  actions are specified in `recording-cloud`.

## Impact

- **New code**
  - `cloud-server/`: worker, D1 schema, deploy script.
  - `FernsyCore`: crypto format, cloud API client, key sync via CloudKit.
  - `FernsyPlayer`: `CloudByteSource`, which decrypts while streaming through the existing
    `ByteSource` interface. FFmpeg does not change.
- **Apps**
  - Mac: Recordings section and upload queue.
  - iOS: a new Recordings section.
  - tvOS: the Recordings screen.
  - Settings on all three: cloud account and subscription.
- **Entitlements**: Sign in with Apple and In-App Purchase on all three apps. The Mac already
  has `network.client`. The existing CloudKit container keeps the key.
- **Accounts and infrastructure**: an R2 bucket, a D1 database, an App Store Connect
  subscription product and an App Store Server API key. App Store Server Notifications point
  at the worker. Two workers: `fernsy-cloud-dev` for tests and `fernsy-cloud` for users.
- **Strings**: new English and German strings in the string catalogs.
