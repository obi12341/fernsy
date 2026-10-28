## MODIFIED Requirements

### Requirement: First launch and sign-in on Apple TV
Without an account, the Apple TV app SHALL show a welcome screen (Fernsy brings no content)
with an IPTV account and a Jellyfin server as two cards; iCloud logins SHALL be used at launch
without it (icloud-sync) and offered first when it shows. Each form SHALL ask for server,
username and password (typing on a nearby iPhone works) and keep them in the keychain; the IPTV
form SHALL offer "Demo-Zugang testen". A failed sign-in SHALL say why and keep the values.

#### Scenario: Adding the other account
- **WHEN** an IPTV account is signed in and the user opens Settings › Konto hinzufügen
- **THEN** the Jellyfin server is offered, and signing in adds the Jellyfin tab

#### Scenario: Signing in to a provider
- **WHEN** the user enters a valid server, username and password and chooses "Anmelden"
- **THEN** the app signs in, stores the credentials in the keychain and opens Start

#### Scenario: Trying the demo
- **WHEN** the user chooses "Demo-Zugang testen"
- **THEN** the app signs in to the demo server and shows its channels, films and series

#### Scenario: Wrong password
- **WHEN** the provider rejects the credentials
- **THEN** the form stays open with the values entered and says that the credentials were rejected

#### Scenario: Signing in to Jellyfin
- **WHEN** the user chooses the Jellyfin card and signs in to a Jellyfin server
- **THEN** the Jellyfin tab appears and the session is kept in the keychain

#### Scenario: Logins from iCloud
- **WHEN** the Mac's provider login is in the user's iCloud and the Apple TV app starts without an account
- **THEN** the app shows "Anmelden …" and opens Start signed in, without the welcome screen

#### Scenario: Offer after signing out
- **WHEN** the user signs out of the provider in Settings while its login is in iCloud
- **THEN** the welcome screen shows the provider's server and user with "Übernehmen", which signs in without the form
