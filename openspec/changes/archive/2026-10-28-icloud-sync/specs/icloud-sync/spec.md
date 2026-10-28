## Purpose

Keep the user's choices and account logins the same on all their Fernsy devices (Mac and Apple
TV) through their own iCloud, without a server of Fernsy's.

## ADDED Requirements

### Requirement: Synced choices
With "Mit iCloud abgleichen" on, the apps SHALL sync through the user's iCloud, per provider
account: hidden categories and channels, favourites, recently watched channels, pinned
categories and resume positions of provider films and episodes; and for the app: preferred
audio and subtitle languages and recording padding. A change SHALL reach the user's other
signed-in devices without a restart while their app runs.

#### Scenario: Hiding on the Mac
- **WHEN** the user hides the category "Sport UK" on the Mac
- **THEN** the Apple TV app of the same Apple ID no longer shows it in Live TV, the guide and zapping

#### Scenario: Continuing a film
- **WHEN** the user stops a provider film at 42 minutes on the Apple TV and opens it on the Mac
- **THEN** the Mac offers to resume at 42 minutes

#### Scenario: Not synced
- **WHEN** a recording is scheduled on the Mac
- **THEN** it does not appear on the Apple TV

### Requirement: Synced conflicts
When two devices changed the same value, the newer change SHALL win, per value. Channel and
category ids unknown to a device's current catalog SHALL be kept, not removed.

#### Scenario: Two changes offline
- **WHEN** the Mac hides channel A offline and the Apple TV later unhides it while online
- **THEN** both devices show channel A once the Mac is online again

### Requirement: Synced accounts
With "Zugangsdaten abgleichen" on, the IPTV login and the Jellyfin server, user and password
SHALL sync end-to-end encrypted through the user's iCloud. Jellyfin sessions and device ids
SHALL NOT sync; each device signs in as its own device. Signing out on one device SHALL NOT
sign out the others.

#### Scenario: New Apple TV
- **WHEN** the user opens the Apple TV app for the first time and the Mac's logins are in their iCloud
- **THEN** the welcome screen offers to use the provider and Jellyfin from the Mac, and choosing it signs in without typing

#### Scenario: Signing out on the Apple TV
- **WHEN** the user signs out of the provider on the Apple TV
- **THEN** the Mac stays signed in

### Requirement: Sync switches
Both apps SHALL offer "Mit iCloud abgleichen" and "Zugangsdaten abgleichen" in their settings,
on by default. Turning one off SHALL keep the device's current values and stop sending and
receiving them. Debug builds SHALL sync only with debug builds.

#### Scenario: Turning sync off
- **WHEN** the user turns off "Mit iCloud abgleichen" on the Apple TV and hides a channel there
- **THEN** the Mac still shows the channel, and the Apple TV keeps its earlier hidden channels

### Requirement: Without iCloud
Without iCloud (signed out, unavailable or offline) the apps SHALL work with their local values
and say so in the settings; changes made meanwhile SHALL sync once iCloud is available again.

#### Scenario: Offline change
- **WHEN** the Mac is offline and the user adds a favourite
- **THEN** the favourite shows on the Mac at once and on the Apple TV after the Mac is back online
