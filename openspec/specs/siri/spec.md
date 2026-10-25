# siri Specification

## Purpose
Voice and system-wide control of Fernsy through App Intents: Siri phrases, Spotlight and the
Shortcuts app, with the same rules as the app.

## Requirements

### Requirement: App Shortcut phrases
Fernsy SHALL offer App Shortcuts in German and English, each phrase containing the app's name:
switch to a channel, what is on now on the favourites, when a show is on, record what the player
shows, and stop playback. They SHALL be available to Siri, Spotlight and the Shortcuts app
without setup by the user.

#### Scenario: Switching by voice
- **WHEN** the user says "Schalte Fernsy auf ZDF" while Fernsy runs
- **THEN** Fernsy plays ZDF and Siri confirms the channel

#### Scenario: What's on
- **WHEN** the user asks "Was läuft gerade in Fernsy?"
- **THEN** Siri answers with the current shows on the favourite channels and shows them as a list

#### Scenario: In the Shortcuts app
- **WHEN** the user opens the Shortcuts app
- **THEN** Fernsy's actions are listed and can be used in shortcuts and automations

### Requirement: Channels as indexed entities
Visible channels SHALL be app entities in the Spotlight semantic index, so Siri resolves spoken
channel names, with favourites and recently watched as suggested values. Hidden channels and
adult channels (per Settings) SHALL NOT be indexed or resolved, and the index SHALL follow
catalog and visibility changes.

#### Scenario: Spoken name
- **WHEN** the user says "Schalte Fernsy auf das Zweite"
- **THEN** Siri resolves the channel named ZDF

#### Scenario: Hidden channel
- **WHEN** a channel is hidden in Fernsy
- **THEN** Siri cannot switch to it and Spotlight does not list it

### Requirement: Onscreen context
The player SHALL expose the playing channel as the onscreen entity, so "this" in a request
refers to it; "Nimm das in Fernsy auf" SHALL record the show on now on that channel with the
app's padding and stream-limit rules and answer with the result.

#### Scenario: Record this
- **WHEN** the player shows Das Erste and the user says "Nimm das in Fernsy auf"
- **THEN** the current show on Das Erste is scheduled and Siri says from when to when it records

### Requirement: Same rules as the app
Intents SHALL follow the app's rules: visibility and adult settings, the IPTV films/series
switches, and the stream limit. Switching SHALL NOT end a running recording; Siri SHALL say which
recording holds the stream instead.

#### Scenario: Recording holds the stream
- **WHEN** the account allows one stream, a recording runs on channel A and the user asks Siri to switch to channel B
- **THEN** nothing changes and Siri says that the recording on channel A holds the stream
