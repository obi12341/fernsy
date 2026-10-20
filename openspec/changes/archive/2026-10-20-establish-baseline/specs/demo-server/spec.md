## Purpose

A public Xtream Codes server with fictional, freely licensed content, so App Review and
developers can use every feature without a real IPTV subscription.

## ADDED Requirements

### Requirement: Demo login
The demo server SHALL accept username `demo` and password `demo` at
https://fernsy-demo.mobilistics.workers.dev and reject other credentials.

#### Scenario: App Review signs in
- **WHEN** a reviewer enters the demo server and demo/demo
- **THEN** the full catalog is shown

### Requirement: Fictional content only
All channels, shows, movies, series, logos and posters SHALL be fictional; videos SHALL be
the Blender Foundation open movies (CC BY 3.0). Content language SHALL follow the app's
Accept-Language (German or English).

#### Scenario: English app
- **WHEN** the app sends an English Accept-Language
- **THEN** channel names, program titles and posters are English

### Requirement: Realistic live channels
Live channels SHALL behave like a live feed: each request starts at the current position of
a looped recording, data arrives at real-time pace after a short lead, and connections
close after about 75 s so reconnect handling is exercised.

#### Scenario: Watching a live channel for two minutes
- **WHEN** a live channel plays for two minutes
- **THEN** the app reconnects once and playback continues without rebuffering

### Requirement: Program guide data
The server SHALL deliver a deterministic schedule per channel from six hours back to three
days ahead, stable within a day.

#### Scenario: Guide
- **WHEN** the guide loads a demo channel
- **THEN** shows are listed for the next three days

### Requirement: Seekable on-demand media
Movies and episodes SHALL redirect to a media file that supports range requests.

#### Scenario: Seeking in a demo movie
- **WHEN** the user seeks in a demo movie
- **THEN** playback continues at the new position
