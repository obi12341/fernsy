## MODIFIED Requirements

### Requirement: First launch and sign-in on Apple TV
Without an account, the Apple TV app SHALL show a welcome screen that explains that Fernsy
brings no content and offers an IPTV account and a Jellyfin server as two cards; logins found in
the user's iCloud SHALL be offered first. Each form SHALL ask for server address, username and
password (typing on a nearby iPhone works) and keep them in the keychain; the IPTV form SHALL
also offer "Demo-Zugang testen". A failed sign-in SHALL say why and keep the entered values.

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
- **THEN** the welcome screen shows the provider's server and user with "Übernehmen", which signs in without the form

### Requirement: Settings on Apple TV
Settings SHALL list the signed-in accounts with their state, "Konto hinzufügen", Wiedergabe
(the playback options the Mac app has), Aufnahmen (padding before and after), iCloud (the two
sync switches and whether iCloud is available), Protokoll (the app log) and the app's version.
Choosing an account SHALL offer signing out.

#### Scenario: Changing the padding
- **WHEN** the user sets the padding to 2 minutes before and 5 after
- **THEN** newly scheduled recordings use it, and the settings row shows "Vorlauf 2 · Nachlauf 5 Min."

#### Scenario: iCloud not available
- **WHEN** the Apple TV is not signed in to iCloud
- **THEN** Settings › iCloud says that syncing needs iCloud, and the app keeps working with its own values
