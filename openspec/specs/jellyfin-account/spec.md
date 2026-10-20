# jellyfin-account Specification

## Purpose
Lets a user connect Fernsy to their own Jellyfin media server, alongside or instead of an
IPTV account, and keeps that session until they sign out.

## Requirements

### Requirement: Choose the account type when signing in
The login screen SHALL offer IPTV (Xtream Codes) and Jellyfin. Settings SHALL offer adding
the other account type while one is signed in.

#### Scenario: First launch
- **WHEN** no account is signed in
- **THEN** the login screen lets the user pick "IPTV" or "Jellyfin"

#### Scenario: Adding Jellyfin to an IPTV account
- **WHEN** the user is signed in to IPTV and chooses "Add Jellyfin server" in Settings
- **THEN** the Jellyfin sign-in opens and the IPTV library stays available

### Requirement: Sign in with server, username and password
Jellyfin sign-in SHALL take a server URL, username and password, check that the server is
a Jellyfin server and authenticate the user.

#### Scenario: Valid login
- **WHEN** the user enters a reachable Jellyfin server and correct credentials
- **THEN** the Jellyfin group appears in the sidebar and its libraries load

#### Scenario: Not a Jellyfin server
- **WHEN** the URL does not answer like a Jellyfin server
- **THEN** sign-in fails with a message saying no Jellyfin server was found there

#### Scenario: Wrong password
- **WHEN** the server rejects the credentials
- **THEN** sign-in fails with "Username or password is wrong" and nothing is stored

### Requirement: Session kept and renewed automatically
The app SHALL keep the Jellyfin session (server, user id, access token) and the password in the
keychain. Relaunching restores the session. When the server rejects the token, Fernsy SHALL
sign in again with the stored password without asking and repeat the request; only when that
fails SHALL it show that the Jellyfin session has expired and offer to sign in again.

#### Scenario: Relaunch
- **WHEN** the user quits and reopens Fernsy
- **THEN** the Jellyfin group is available without signing in again

#### Scenario: Token revoked on the server
- **WHEN** the session was ended on the server (e.g. device removed in the dashboard)
- **THEN** Fernsy signs in again by itself and the library keeps working without a notice

#### Scenario: Password changed
- **WHEN** the token is rejected and the stored password no longer works
- **THEN** Fernsy shows that the Jellyfin session has expired and offers to sign in again

### Requirement: Both accounts at the same time
An IPTV account and one Jellyfin account SHALL be usable at the same time; signing out of
one SHALL NOT affect the other. The library window is shown when at least one account is
signed in.

#### Scenario: Signing out of IPTV
- **WHEN** both accounts are signed in and the user signs out of IPTV
- **THEN** the IPTV sections disappear and the Jellyfin group stays

### Requirement: Sign out of Jellyfin
Settings SHALL show the Jellyfin server name, version and user, and offer "Sign Out", which
ends the session on the server where possible and removes the session and the password from
the keychain.

#### Scenario: Sign out
- **WHEN** the user signs out of Jellyfin
- **THEN** the Jellyfin group disappears and the keychain entries (session and password) are
  deleted

### Requirement: Fernsy identifies itself as a client
Requests SHALL identify Fernsy (client name, version, a stable device id and the Mac's
name) so the server's dashboard lists it as its own device. Debug builds SHALL use a device id
of their own, so signing in or out with a debug build never ends the installed app's session.

#### Scenario: Server dashboard
- **WHEN** the admin opens the server's device list
- **THEN** Fernsy appears with the Mac's name

#### Scenario: Debug build next to the installed app
- **WHEN** a debug build signs in to the same server with the same user
- **THEN** the installed app stays signed in
