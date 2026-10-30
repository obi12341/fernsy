# recording-cloud Specification

## Purpose
Lets a user upload recordings made on the Mac to a private, end-to-end encrypted Fernsy Cloud
storage and stream them on every Fernsy app (Mac, iPad, iPhone, Apple TV), without the
operator being able to read what is stored.

## Requirements

### Requirement: End-to-end encrypted uploads
Recording data SHALL be encrypted on the Mac before it leaves the device, and decrypted only on
the user's devices. Fernsy Cloud SHALL receive only ciphertext; no key, title, channel name or
program detail SHALL be sent to it in readable form.

#### Scenario: What the server stores
- **WHEN** a recording "Tagesschau" from "Das Erste" is uploaded
- **THEN** the stored objects have random ids and their bytes contain neither the title, the channel name nor any MPEG-TS packet in plain form

#### Scenario: Tampered data
- **WHEN** a stored chunk is changed or chunks are swapped or cut off
- **THEN** playback of that recording reports it as damaged instead of playing altered data

### Requirement: Encrypted recording details
A cloud recording's details (title, channel, show time, recording window, duration, size,
gaps and outcome) SHALL be stored only encrypted with the user's key, so every device shows
them while the server sees only sizes and upload times.

#### Scenario: Details on the Apple TV
- **WHEN** the Apple TV lists a recording uploaded from the Mac
- **THEN** it shows the same title, channel and time as the Mac's Recordings section

### Requirement: Key shared through the user's iCloud
The user's cloud key SHALL be created on first use and kept in the device keychain and in the
user's private, end-to-end encrypted iCloud data, so every device signed in to the same Apple
ID gets it without the user typing anything. The key SHALL never be sent to Fernsy Cloud.

#### Scenario: Second device
- **WHEN** a user who uploaded from the Mac opens the cloud recordings on their iPad for the first time
- **THEN** the iPad fetches the key from iCloud and plays the recordings

#### Scenario: No key available
- **WHEN** a device with an active subscription finds a key record in iCloud but cannot read it, or iCloud is unavailable
- **THEN** the app lists the recordings as locked and explains that the key comes from iCloud of the same Apple ID, without offering to create a new key that would replace the existing one

#### Scenario: First key on the Apple TV
- **WHEN** a user subscribes on the Apple TV and no key exists in their iCloud yet
- **THEN** the Apple TV creates the key, and the Mac later uses that same key for its uploads

#### Scenario: Two devices create a key at once
- **WHEN** the Mac and the iPad both create a key at the same moment
- **THEN** both end up with the same key, and no recording is sealed with the other one

### Requirement: Global cloud switch on the Mac
Settings › Aufnahmen SHALL offer "Upload recordings to Fernsy Cloud" (default off). Turning it
on SHALL require an active subscription, offering to buy or restore it; no other prompt SHALL
follow. While on, every recording that finishes with data SHALL be queued for upload. Turning
it off SHALL stop uploading and keep what is stored.

#### Scenario: Turning on without a subscription
- **WHEN** the user turns the switch on without a subscription
- **THEN** the app offers to subscribe or restore, and the switch turns on as soon as the purchase or restore succeeds

#### Scenario: Turning on with a subscription
- **WHEN** the user turns the switch on with an active subscription
- **THEN** the switch is on at once, without any sign-in prompt

#### Scenario: Recording finishes
- **WHEN** the switch is on and a scheduled recording ends
- **THEN** the recording is queued and uploads without further action

#### Scenario: Failed recording
- **WHEN** the switch is on and a recording fails without any data
- **THEN** it is not queued

### Requirement: Subscription
Fernsy Cloud SHALL require an auto-renewable in-app subscription that can be bought and
restored in every app, the Apple TV included. Apple's purchase confirmation SHALL be the only
dialog. Settings SHALL show its state (none, active with used and total storage, ending or
ended with dates).

#### Scenario: Restore
- **WHEN** a user who subscribed on the iPad turns the switch on on the Mac and chooses "Restore purchases"
- **THEN** the subscription counts as active and the switch is on, without a sign-in

#### Scenario: Subscribing on the Apple TV
- **WHEN** a user whose Mac runs Fernsy subscribes in the Apple TV's settings
- **THEN** after Apple's purchase confirmation the Apple TV shows the subscription as active, and the Mac's switch can be turned on without buying again

### Requirement: Upload of earlier recordings
While the cloud switch is on, every finished recording in the Recordings section that is not
in the cloud SHALL offer "Upload to Fernsy Cloud". Running, waiting and scheduled recordings
SHALL NOT be uploadable.

#### Scenario: Uploading an older recording
- **WHEN** the switch is on and the user chooses "Upload to Fernsy Cloud" on a recording from last week
- **THEN** its row shows the upload progress and, when done, that it is in the cloud

#### Scenario: Running recording
- **WHEN** a recording is still running
- **THEN** it has no upload action

### Requirement: Resumable uploads
Uploads SHALL run while Fernsy runs, one at a time in queue order. An upload that is
interrupted (network loss, quit, sleep) SHALL continue where it stopped when Fernsy runs and
the network is back, without starting over. The user SHALL be able to cancel a queued or running upload.

#### Scenario: Quit during upload
- **WHEN** Fernsy is quit at 60 % of an upload and opened again later
- **THEN** the upload continues from about 60 %

#### Scenario: Cancel
- **WHEN** the user cancels a running upload
- **THEN** nothing of it stays in the cloud and the recording shows no cloud state

### Requirement: Quota
An upload SHALL be refused before it starts when the recording does not fit into the free
storage of the subscription, with a message naming the needed and the free space.

#### Scenario: Cloud full
- **WHEN** a 3 GB recording is uploaded with 1 GB free
- **THEN** the upload does not start and the message names 3 GB needed and 1 GB free

### Requirement: Cloud recordings on every device
The Mac's Recordings section SHALL mark cloud recordings and list cloud-only ones. With an
active subscription, iPad and iPhone SHALL have a Recordings section and the Apple TV's
Recordings screen SHALL list cloud recordings, newest first, with title, channel, time and
duration, without any sign-in.

#### Scenario: First use on the Apple TV
- **WHEN** a subscriber opens Recordings on the Apple TV for the first time
- **THEN** the cloud recordings are listed without any prompt

#### Scenario: Recording deleted locally
- **WHEN** a recording was uploaded and then moved to the Trash on the Mac
- **THEN** the Mac still lists it as a cloud recording that can be played

### Requirement: Streaming cloud recordings
Cloud recordings SHALL play by streaming, starting within seconds without downloading the
whole file first, with seeking, resume position and the player features that local
recordings have. Streaming SHALL NOT use a provider connection.

#### Scenario: Seeking on the Apple TV
- **WHEN** a two-hour cloud recording plays on the Apple TV and the user jumps to 1:30
- **THEN** playback continues at 1:30 within a few seconds

#### Scenario: Single-stream account
- **WHEN** a cloud recording plays while a recording on the Mac holds the account's only stream
- **THEN** both continue; nothing asks for the provider connection

### Requirement: Deleting cloud recordings
Every app SHALL be able to delete a cloud recording after confirmation. Deleting SHALL free
its storage and remove it from all devices; the local file on the Mac SHALL stay.

#### Scenario: Delete on the iPad
- **WHEN** the user deletes a cloud recording on the iPad and confirms
- **THEN** it disappears from the cloud lists on all devices and the free storage grows by its size

### Requirement: Subscription end
When the subscription ends, uploads SHALL stop and stored recordings SHALL stay playable and
deletable for 30 days. The apps SHALL show the date after which they are deleted. Renewing
before that date SHALL keep them.

#### Scenario: Subscription lapsed
- **WHEN** a subscription ended 10 days ago
- **THEN** the cloud recordings play, uploads are not offered, and a note says they are deleted in 20 days unless renewed

### Requirement: No account prompt
No app SHALL ask the user to sign in, create an account or confirm an identity for Fernsy
Cloud. A device that has the key SHALL use the user's Fernsy Cloud account on its own.

#### Scenario: Second device after purchase
- **WHEN** a user subscribed on the Mac and opens Fernsy on their iPad with the same Apple ID
- **THEN** the iPad shows the subscription and the cloud recordings without any prompt

#### Scenario: User without subscription
- **WHEN** a user who never subscribed uses the apps
- **THEN** nothing asks for a sign-in, and only the offer is shown

### Requirement: Offer only with a Mac
iPad, iPhone and Apple TV SHALL offer the subscription only when Fernsy on a Mac is known in
the user's iCloud. Without one, Settings › Fernsy Cloud SHALL explain that Fernsy on a Mac with
the same Apple ID records, instead of offering to subscribe. The Mac SHALL always offer it.

#### Scenario: Apple TV without a Mac
- **WHEN** a user who never ran Fernsy on a Mac opens Settings › Fernsy Cloud on the Apple TV
- **THEN** no subscribe button is shown, and a note says that Fernsy on a Mac with the same Apple ID is needed

#### Scenario: Apple TV with a Mac
- **WHEN** the user has run Fernsy on a Mac with the same Apple ID
- **THEN** the Apple TV offers to subscribe and to restore

#### Scenario: Existing subscriber
- **WHEN** a subscriber with no Mac marker opens the settings on the iPad
- **THEN** the subscription and the cloud recordings are shown as usual

### Requirement: Moving the subscription to a new key
When the device's subscription belongs to a different Fernsy Cloud account than the device's
key, for example after the key was lost and a new one created, the app SHALL offer to move the
subscription to this key. The account the purchase was made for SHALL be able to take it back.

#### Scenario: Key lost
- **WHEN** a subscriber's iCloud data for Fernsy was deleted, a new key was created, and the user chooses to move the subscription
- **THEN** the subscription counts for the new key, and the old recordings, which nobody can read any more, are deleted after the grace period

#### Scenario: Take-back
- **WHEN** someone moved a subscription away from the account it was bought for, and a device with that account's key opens Fernsy Cloud
- **THEN** the subscription is linked to the original account again without a prompt

### Requirement: Deleting all cloud data
Settings › Fernsy Cloud SHALL offer "Delete Fernsy Cloud data" after confirmation. It SHALL
delete all of the user's cloud recordings and their account on the server, and say that the
subscription is managed and cancelled in the App Store. The local files on the Mac SHALL stay.

#### Scenario: Deleting
- **WHEN** a subscriber chooses "Delete Fernsy Cloud data" on the iPad and confirms
- **THEN** no cloud recording is listed on any device afterwards, and the app shows where to cancel the subscription

#### Scenario: Using it again
- **WHEN** a user deleted their cloud data and the subscription is still active
- **THEN** the next upload works with the same key and an empty storage

### Requirement: Upload throughput
While one recording uploads, the Mac SHALL send several of its parts at the same time, so that
a single upload can use most of the user's upstream bandwidth instead of waiting for each part
before sending the next. At most four parts SHALL be in flight at once. Parts that finished
SHALL count as uploaded even when earlier parts are still missing, and resuming SHALL upload
only the parts that are missing.

#### Scenario: Several parts in flight
- **WHEN** a 3 GB recording uploads
- **THEN** up to four of its parts are sent at the same time, never more

#### Scenario: Resume after parts finished out of order
- **WHEN** an upload is interrupted after parts 1, 2 and 4 finished but part 3 did not
- **THEN** after Fernsy runs again only part 3 and the parts after 4 are uploaded, and the recording in the cloud plays from start to end

#### Scenario: Cancel while parts are in flight
- **WHEN** the user cancels an upload while several parts are being sent
- **THEN** the sending stops, nothing of it stays in the cloud and the recording shows no cloud state
