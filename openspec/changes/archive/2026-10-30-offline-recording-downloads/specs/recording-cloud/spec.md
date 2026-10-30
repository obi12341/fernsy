# Spec Delta

## MODIFIED Requirements

### Requirement: Cloud recordings on every device
The Mac's Recordings section SHALL mark cloud recordings and list cloud-only ones. With an
active subscription, iPad and iPhone SHALL have a Recordings section and the Apple TV's
Recordings screen SHALL list cloud recordings, newest first, with title, channel, time and
duration, without any sign-in. iPad and iPhone SHALL also show the Recordings section, with the
downloaded recordings, whenever downloads exist, with or without a subscription or a
connection.

#### Scenario: First use on the Apple TV
- **WHEN** a subscriber opens Recordings on the Apple TV for the first time
- **THEN** the cloud recordings are listed without any prompt

#### Scenario: Recording deleted locally
- **WHEN** a recording was uploaded and then moved to the Trash on the Mac
- **THEN** the Mac still lists it as a cloud recording that can be played

#### Scenario: Downloads without a subscription
- **WHEN** the subscription ended months ago and the iPad still holds two downloads
- **THEN** the Recordings section shows those two recordings

## ADDED Requirements

### Requirement: Downloading cloud recordings on iPad and iPhone
On iPad and iPhone, each cloud recording that the device can read SHALL offer "Download". A
download SHALL continue while the app is in the background or closed, show its progress on the
recording's row, survive a lost connection by continuing later, and be cancellable. A download
SHALL be refused before it starts when the device has less free space than the recording plus
a margin, and SHALL say how much is needed. The Apple TV and the Mac SHALL NOT offer downloads.

#### Scenario: Download and lock the iPad
- **WHEN** the user taps "Download" on a 3 GB recording and locks the iPad
- **THEN** the download continues, and on the next look the row shows the recording as downloaded

#### Scenario: Not enough space
- **WHEN** the user downloads a 3 GB recording with 1 GB free on the iPad
- **THEN** nothing is downloaded and the message names 3 GB needed and 1 GB free

#### Scenario: Cancel
- **WHEN** the user cancels a running download
- **THEN** its partial data is removed and the row offers "Download" again

### Requirement: Playing downloads offline
A downloaded recording SHALL play from the device with seeking and resume position, without a
network connection, a reachable server or an active subscription. It SHALL stay encrypted on
the device as stored in the cloud and be decrypted only while it plays. Downloads SHALL be kept
where iOS does not clear them and SHALL NOT be included in device backups.

#### Scenario: Airplane mode
- **WHEN** the iPad is in airplane mode and the user plays a downloaded recording
- **THEN** it starts at once, and jumping to 1:30 continues there at once

#### Scenario: Stays encrypted
- **WHEN** a downloaded recording's file is copied off the device
- **THEN** it holds no readable video, title or channel

### Requirement: Downloads after the subscription ends
A downloaded recording SHALL stay on the device and playable after the subscription ends and
after the server deleted its cloud copy at the end of the grace period. It SHALL be removed
only by the user on the device, or by a deletion of its cloud copy while the subscription is
active.

#### Scenario: Grace period over
- **WHEN** the subscription ended 40 days ago, the cloud copies are gone, and the iPad goes online
- **THEN** the downloads stay and still play

### Requirement: Removing downloads
A downloaded recording SHALL offer "Remove Download", which frees its space and keeps the cloud
copy. While the subscription is active and the cloud list was loaded, a download whose cloud
recording no longer exists SHALL be removed, so a deletion on any device, and "Delete Fernsy
Cloud Data", removes it everywhere. Settings SHALL show the space all downloads use.

#### Scenario: Deleted on the Mac
- **WHEN** a recording downloaded on the iPad is deleted from Fernsy Cloud on the Mac while the subscription is active
- **THEN** the next time the iPad loads the cloud list, the download is removed too

#### Scenario: Remove on the iPad only
- **WHEN** the user chooses "Remove Download" on the iPad
- **THEN** the download's space is freed and the recording stays in the cloud and streamable
