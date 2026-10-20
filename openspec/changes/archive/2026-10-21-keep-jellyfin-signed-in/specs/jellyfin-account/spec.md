## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Session kept without the password
**Reason**: The user wants to never sign in by hand again; renewing a rejected token needs the
password.
**Migration**: See "Session kept and renewed automatically"; accounts signed in before this
change sign in once more, after which the password is stored.

## MODIFIED Requirements

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
