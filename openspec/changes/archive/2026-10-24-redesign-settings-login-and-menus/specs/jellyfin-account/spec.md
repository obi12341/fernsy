## MODIFIED Requirements

### Requirement: Choose the account type when signing in
The login screen SHALL offer IPTV (Xtream Codes) and Jellyfin as two cards that say what
each source provides. Settings SHALL offer adding
the other account type while one is signed in.

#### Scenario: First launch
- **WHEN** no account is signed in
- **THEN** the login screen lets the user pick "IPTV" or "Jellyfin"

#### Scenario: Adding Jellyfin to an IPTV account
- **WHEN** the user is signed in to IPTV and chooses "Add Jellyfin server" in Settings
- **THEN** the Jellyfin sign-in opens and the IPTV library stays available
