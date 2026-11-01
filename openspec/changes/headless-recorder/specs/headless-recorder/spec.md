## Purpose
Fernsy Server: a headless recorder in a Docker container that plans and runs one user's IPTV
recordings around the clock, controlled from the Fernsy apps through the user's iCloud and
uploading its recordings end-to-end encrypted to Fernsy Cloud.

## ADDED Requirements

### Requirement: Docker image
Fernsy Server SHALL be published as a Docker image for linux/amd64 and linux/arm64 (Raspberry Pi
4 and newer) that runs without a display, keeps its state in one volume and survives restarts
with its pairing and pending orders. Its FFmpeg, when used, SHALL be LGPL-only like the apps'.

#### Scenario: Raspberry Pi
- **WHEN** the user runs the image with a volume on a Raspberry Pi 4
- **THEN** the server starts and shows a pairing code in its log and on its status page

#### Scenario: Restart
- **WHEN** the container restarts while orders are pending
- **THEN** it comes back paired and keeps the orders

### Requirement: Pairing with an app
A new server SHALL show a short pairing code. Entering it in an app (Settings › Fernsy Cloud ›
Server) SHALL hand the server the user's Fernsy Cloud key, the IPTV login it records with and
access to the user's private CloudKit data, encrypted for that server only. The user SHALL be
able to remove the server in the app, after which it holds no secrets and can be paired anew.

#### Scenario: Pairing
- **WHEN** the user enters the server's code on the iPhone
- **THEN** the app shows the server as connected, and the server's log says it is paired

#### Scenario: Removing
- **WHEN** the user removes the server in the app
- **THEN** the server deletes its keys and login and shows a new pairing code

### Requirement: Orders from the apps
The server SHALL take recording orders that the apps write to the user's private iCloud data,
apply the recording rules of the apps (padding, stream limit, overlaps, missed shows), and write
back each order's state: scheduled, recording, uploading, done, failed with a reason, refused with
a reason. A cancelled order SHALL be dropped, and stopped while it runs.

#### Scenario: Scheduled on the Apple TV
- **WHEN** the user schedules tonight's show for the server on the Apple TV
- **THEN** the order shows "scheduled" on every device within a minute

#### Scenario: Over the stream limit
- **WHEN** an order would exceed the account's stream limit with the server's other recordings
- **THEN** it is refused and the apps show why

### Requirement: Recording and upload
The server SHALL record the channel's stream into a file from start minus padding to end plus
padding, reconnect when the stream breaks and mark the gaps, and after the end encrypt the file
with the user's key and upload it to Fernsy Cloud; the local file SHALL be deleted after a
successful upload. Recording SHALL need an active subscription.

#### Scenario: Show recorded
- **WHEN** a scheduled show ends
- **THEN** the recording appears in Fernsy Cloud on every device and the server keeps no copy

#### Scenario: Subscription ended
- **WHEN** the subscription is not active at a recording's start
- **THEN** the order fails with that reason and nothing is recorded

### Requirement: Server status
The server SHALL report its state (paired, last contact, free space, running and next
recordings, errors) to the apps through the user's iCloud and on a local status page, and log
without credentials, keys or stream URLs.

#### Scenario: Server offline
- **WHEN** the server has not reported for 10 minutes
- **THEN** the apps show it as offline with the time of its last contact
