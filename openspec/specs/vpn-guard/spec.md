# vpn-guard Specification

## Purpose

Lets users make sure that Fernsy contacts their IPTV provider only while the device's internet
traffic runs through a VPN, and defines what the apps hold back, show and resume around that.

## Requirements

### Requirement: Setting "IPTV only with VPN"
The Mac, iPhone/iPad and Apple TV apps SHALL each offer a setting "IPTV only with VPN" in the IPTV
account's settings. It SHALL be off by default and SHALL be kept per device: it is not synced
through iCloud. Next to the setting the app SHALL say whether it currently sees a VPN, also while
the setting is off, so that the user can check the detection before relying on it.

#### Scenario: Off by default
- **WHEN** a user installs or updates Fernsy and never touches the setting
- **THEN** Fernsy contacts the provider with and without a VPN, as before

#### Scenario: Kept across launches
- **WHEN** the user switches the setting on and opens Fernsy again later
- **THEN** the setting is still on

#### Scenario: Not carried to other devices
- **WHEN** the user switches the setting on on the Mac, with iCloud sync on
- **THEN** the setting on their Apple TV stays as it was

#### Scenario: Detection shown
- **WHEN** the user opens the setting while a VPN app is connected, and again after disconnecting it
- **THEN** the app says that a VPN is connected the first time and that none is the second time

### Requirement: What counts as a VPN
A VPN SHALL count as connected when the device's general internet traffic leaves through a VPN
tunnel, whichever VPN app set it up. A VPN that is connected but carries only the traffic of its
own network SHALL NOT count, and neither SHALL a tunnel that carries only one of the address
families the device can reach the internet with. The apps SHALL NOT ask for a VPN provider, server
or location.

#### Scenario: VPN app connected
- **WHEN** a VPN app routes all of the device's traffic through its tunnel
- **THEN** Fernsy sees a VPN

#### Scenario: Split tunnel
- **WHEN** a VPN is connected that only reaches a private network, and the internet is reached directly
- **THEN** Fernsy sees no VPN

#### Scenario: IPv6 beside the tunnel
- **WHEN** a VPN tunnels IPv4 only and the device also reaches the internet directly over IPv6
- **THEN** Fernsy sees no VPN

#### Scenario: VPN on the router
- **WHEN** the home router sends everything through a VPN and no VPN runs on the device
- **THEN** Fernsy sees no VPN, and the user leaves the setting off on this device

### Requirement: No request to the provider without a VPN
While the setting is on and no VPN counts as connected, the apps SHALL NOT send any request to the
IPTV provider or for its content: sign-in, catalog and guide requests, live, film, episode and
catch-up streams, recordings, and artwork of IPTV items that is not cached. An action that needs
such a request SHALL fail with a message that names the missing VPN, whether it was started in the
app, by Siri, by the assistant or through the MCP server.

#### Scenario: Starting a channel
- **WHEN** the setting is on, no VPN is connected, and the user starts a channel
- **THEN** no connection to the provider is opened and the player says that no VPN is connected

#### Scenario: Catalog and guide
- **WHEN** the setting is on, no VPN is connected, and the catalog or a channel's guide is due
- **THEN** nothing is requested and the content loaded earlier stays on screen

#### Scenario: Artwork
- **WHEN** the setting is on, no VPN is connected, and a list of channels scrolls into view
- **THEN** logos already cached show, and the others are not downloaded

#### Scenario: Through the MCP server
- **WHEN** the setting is on, no VPN is connected, and an MCP client asks Fernsy to play a channel
- **THEN** the tool answers that no VPN is connected, and nothing is requested from the provider

#### Scenario: VPN connected
- **WHEN** the setting is on and a VPN is connected
- **THEN** everything works as with the setting off

### Requirement: Other connections are not held back
The setting SHALL affect the IPTV provider only. Jellyfin, Fernsy Cloud, a paired Fernsy Server,
iCloud, app updates, and playback of recordings and downloads on the device SHALL work without a
VPN as before.

#### Scenario: Jellyfin without a VPN
- **WHEN** the setting is on, no VPN is connected, and the user plays a Jellyfin film
- **THEN** the film plays

#### Scenario: A recording on the device
- **WHEN** the setting is on, no VPN is connected, and the user plays a finished recording
- **THEN** the recording plays

### Requirement: VPN drops while a stream runs
When the VPN stops counting as connected while a provider stream runs, the app SHALL NOT open a
new connection to the provider for it. The player SHALL say that the VPN is not connected instead
of naming the provider or the network. When the VPN is back, playback SHALL continue without user
action: live at the live edge, a film or episode at its position.

#### Scenario: Live channel
- **WHEN** a channel plays, the VPN drops, and the VPN reconnects half a minute later
- **THEN** the player shows the VPN note in between, no request reaches the provider during that
  time, and the channel plays again by itself

#### Scenario: Film
- **WHEN** a film plays, the VPN drops for good, and the buffered part is played out
- **THEN** the film waits at that position with the VPN note until the VPN is back or the user closes it

### Requirement: Opening the app without a VPN
With a stored IPTV account, the setting on and no VPN connected, the app SHALL open as it does
without a connection, showing what it has cached, and SHALL name the missing VPN as the reason
instead of a connection or sign-in error. When the VPN connects, the app SHALL sign in and load
the catalog without user action.

#### Scenario: Opened before the VPN
- **WHEN** the user opens Fernsy with the setting on and connects the VPN a minute later
- **THEN** the app first shows the cached channels with a note that no VPN is connected, and then
  loads the catalog by itself

### Requirement: Recordings wait for the VPN
A planned recording whose start falls into a time without a VPN SHALL NOT start. It SHALL stay
planned and start as soon as the VPN connects before the show's end; if it does not, the recording
SHALL be marked as missed with the missing VPN as the reason. A running recording SHALL pause its
stream when the VPN drops and go on when it is back, like other interruptions of its connection.

#### Scenario: VPN connects during the show
- **WHEN** a recording is due at 20:15, the VPN is not connected, and it connects at 20:30
- **THEN** the recording starts at 20:30

#### Scenario: No VPN for the whole show
- **WHEN** no VPN connects before the planned show ends
- **THEN** the recording is listed as missed, with the note that no VPN was connected

#### Scenario: VPN drops during a recording
- **WHEN** a recording runs, the VPN drops for two minutes and comes back
- **THEN** the recording goes on and its file has a gap of about two minutes
