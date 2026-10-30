# Spec Delta

## MODIFIED Requirements

### Requirement: Storage on iPhone and iPad
The app SHALL keep the timeshift buffer and caches only where iOS may delete them, and SHALL
work when they are gone. Downloaded Fernsy Cloud recordings are not caches: they SHALL be kept
where iOS does not delete them.

#### Scenario: Caches cleared
- **WHEN** iOS removed the app's caches while it was not running
- **THEN** the app loads the channel list again and plays as usual

#### Scenario: Downloads kept
- **WHEN** iOS removed the app's caches while it was not running
- **THEN** the downloaded cloud recordings are still there and play

## ADDED Requirements

### Requirement: Opening without a connection
With a stored IPTV or Jellyfin account, the app SHALL open into its tabs when it has no
connection or the server is unreachable, also when the cached catalog is gone. It SHALL show the
cached content it has and say that there is no connection, instead of the welcome screen or a
sign-in error. Downloaded recordings SHALL be reachable and play. When the connection returns,
the app SHALL load the catalog without user action. A stored account whose server rejects the
sign-in SHALL behave as before.

#### Scenario: Offline with an empty cache
- **WHEN** iOS removed the app's caches, the iPad is offline, and the user opens Fernsy
- **THEN** the tabs show with a note that there is no connection, and Recordings lists the downloads

#### Scenario: Connection returns
- **WHEN** the app opened offline and the network comes back
- **THEN** the channel list loads without the user doing anything

#### Scenario: Password changed
- **WHEN** the provider rejects the stored account's password while the iPad is online and nothing is cached
- **THEN** the app shows the welcome screen as before, not the tabs with the no-connection note
