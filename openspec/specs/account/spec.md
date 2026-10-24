# account Specification

## Purpose
Lets a user connect Fernsy to their own IPTV provider through the Xtream Codes API and keeps
that login on the Mac until they sign out.

## Requirements

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

### Requirement: Credentials are kept in the keychain
The app SHALL store the accepted credentials in the macOS keychain and sign in with them
automatically at the next launch.

#### Scenario: Relaunch
- **WHEN** the user quits and reopens Fernsy after a successful sign-in
- **THEN** the library opens without asking for credentials again

### Requirement: Sign out removes the login
Settings SHALL offer "Sign Out", which stops playback, removes the stored credentials and
returns to the login form.

#### Scenario: Sign out
- **WHEN** the user chooses Sign Out in Settings
- **THEN** the keychain entry is deleted, the catalog is cleared and the login form is shown

### Requirement: Account information
Settings SHALL show server, username, expiry date and the number of simultaneous
connections the provider reports.

#### Scenario: Settings open
- **WHEN** the user opens Settings while signed in
- **THEN** server, username, "valid until" and maximum connections are listed

### Requirement: The app collects no data
The app SHALL connect only to the provider the user configured and SHALL NOT send
analytics, tracking or credentials anywhere else.

#### Scenario: Network use
- **WHEN** the app runs
- **THEN** all requests go to the configured provider (or the hosts it redirects streams to)
