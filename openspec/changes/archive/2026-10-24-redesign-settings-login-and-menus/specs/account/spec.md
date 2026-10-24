## MODIFIED Requirements

### Requirement: Sign in with Xtream Codes credentials
The app SHALL ask for server URL, username and password and verify them against the
provider's `player_api.php` before showing the library. An error SHALL appear below the
fields it concerns (the server for an unreachable or invalid address, username and password
for rejected credentials), which get a red outline; the note that Fernsy collects no data
stays visible below the form.

#### Scenario: Valid credentials
- **WHEN** the user enters a server, username and password the provider accepts
- **THEN** the library opens and the catalog is downloaded

#### Scenario: Rejected credentials
- **WHEN** the provider reports the account as not authenticated or the server is unreachable
- **THEN** the login form stays open with the error below the fields it concerns
