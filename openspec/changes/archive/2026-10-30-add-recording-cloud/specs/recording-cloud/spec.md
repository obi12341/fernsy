# Spec Delta

## Purpose

Lets a user upload recordings made on the Mac to a private, end-to-end encrypted Fernsy Cloud
storage and stream them on every Fernsy app (Mac, iPad, iPhone, Apple TV), without the
operator being able to read what is stored.

## ADDED Requirements

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
- **WHEN** a device is signed in to Fernsy Cloud but cannot get the key from iCloud
- **THEN** the app lists the recordings as locked and explains that the key comes from iCloud of the same Apple ID, without offering to create a new key that would replace the existing one

### Requirement: Global cloud switch on the Mac
Settings › Aufnahmen SHALL offer "Upload recordings to Fernsy Cloud" (default off). Turning it
on SHALL first require an active subscription, offering to buy or restore it, and then ask for
Sign in with Apple once. While on, every recording that finishes with data SHALL be queued for
upload. Turning it off SHALL stop uploading and keep what is stored.

#### Scenario: Turning on without a subscription
- **WHEN** the user turns the switch on without a subscription
- **THEN** the app offers to subscribe or restore, and the switch stays off until a subscription is active and Sign in with Apple succeeded

#### Scenario: Turning on with a subscription
- **WHEN** the user turns the switch on with an active subscription
- **THEN** Sign in with Apple asks once for confirmation and the switch is on afterwards

#### Scenario: Recording finishes
- **WHEN** the switch is on and a scheduled recording ends
- **THEN** the recording is queued and uploads without further action

#### Scenario: Failed recording
- **WHEN** the switch is on and a recording fails without any data
- **THEN** it is not queued

### Requirement: No sign-in before it is needed
No app SHALL ask for Sign in with Apple, or show Fernsy Cloud places other than the offer,
unless the user has an active subscription (or one in its grace period) and chooses to use
Fernsy Cloud. The session SHALL then last without further prompts while the app is used.

#### Scenario: User without subscription
- **WHEN** a user who never subscribed uses the apps
- **THEN** no Sign in with Apple prompt appears anywhere

### Requirement: Subscription
Fernsy Cloud SHALL require an auto-renewable in-app subscription, bought and restorable in
every app. Settings SHALL show its state (none, active with used and total storage, ending or
ended with dates). Signing out of Fernsy Cloud SHALL leave stored recordings untouched.

#### Scenario: Restore
- **WHEN** a user who subscribed on the iPad turns the switch on on the Mac and chooses "Restore purchases"
- **THEN** the subscription counts as active and Sign in with Apple follows

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
duration; the first use on a device asks for Sign in with Apple once.

#### Scenario: First use on the Apple TV
- **WHEN** a subscriber opens Recordings on the Apple TV for the first time
- **THEN** Sign in with Apple asks once for confirmation and the cloud recordings are listed

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
