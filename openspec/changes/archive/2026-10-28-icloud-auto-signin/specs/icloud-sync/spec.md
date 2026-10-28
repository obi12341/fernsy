## MODIFIED Requirements

### Requirement: Synced accounts
With "Zugangsdaten abgleichen" on, the IPTV login and the Jellyfin server, user and password
SHALL sync end-to-end encrypted through the user's iCloud. Jellyfin sessions and device ids
SHALL NOT sync; each device signs in as its own device. Signing out on one device SHALL NOT
sign out the others. At launch without an account, the apps SHALL sign in with the logins in
iCloud directly, showing their steps and nothing to cancel.

#### Scenario: New Apple TV
- **WHEN** the user opens the Apple TV app for the first time and the Mac's logins are in their iCloud
- **THEN** the app shows "Anmelden …" and opens Start signed in to the provider and Jellyfin, without the welcome screen

#### Scenario: Steps at launch
- **WHEN** the app signs in with the provider login from iCloud at launch
- **THEN** it shows the Fernsy icon with the steps "Zugang in iCloud gefunden", "Bei <server> angemeldet" and "Sender laden …" checked off in turn, for at least 1.5 seconds, and then fades into Start

#### Scenario: Signing out on the Apple TV
- **WHEN** the user signs out of the provider on the Apple TV
- **THEN** the Mac stays signed in, and the Apple TV shows the welcome screen with the iCloud login as an offer

#### Scenario: Next launch after signing out
- **WHEN** the user signed out on the Apple TV and opens the app again later
- **THEN** it signs in with the login in iCloud again

#### Scenario: Login no longer valid
- **WHEN** the provider rejects the login from iCloud at launch
- **THEN** the welcome or login screen shows with the reason and the login as an offer
