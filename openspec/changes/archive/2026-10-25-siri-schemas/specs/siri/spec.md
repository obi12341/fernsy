## REMOVED Requirements

### Requirement: App Shortcut phrases
**Reason**: Siri AI on macOS 27 does not use App Shortcut phrases by voice (tested with nightly build 124: "Schalte Fernsy auf ZDF" and "Was läuft gerade in Fernsy?" were refused), so the spoken scenarios cannot hold.
**Migration**: Replaced by "Shortcuts and Spotlight actions" (the same actions without the voice promise) and "Siri AI schemas" (voice through `.system.open` and `.system.searchInApp`).

### Requirement: Onscreen context
**Reason**: The spoken "Nimm das in Fernsy auf" has no schema in Siri AI; the record action keeps using the onscreen channel.
**Migration**: Replaced by "Onscreen channel for actions".

## MODIFIED Requirements

### Requirement: Channels as indexed entities
Visible channels SHALL be app entities in the Spotlight semantic index, so Siri resolves spoken
channel names, with favourites and recently watched as suggested values. Hidden channels and
adult channels (per Settings) SHALL NOT be indexed or resolved, and the index SHALL follow
catalog and visibility changes.

#### Scenario: Spoken name
- **WHEN** the user tells Siri "Öffne das Zweite in Fernsy"
- **THEN** Siri resolves the channel named ZDF

#### Scenario: Hidden channel
- **WHEN** a channel is hidden in Fernsy
- **THEN** Siri cannot switch to it and Spotlight does not list it

## ADDED Requirements

### Requirement: Shortcuts and Spotlight actions
Fernsy SHALL offer its actions (switch to a channel, what is on now on the favourites, find a
show, record, stop playback) as App Shortcuts with German and English titles and phrases, usable
in the Shortcuts app and Spotlight without setup. Spoken requests to Siri AI go through the
"Siri AI schemas" requirement, not through these phrases.

#### Scenario: In the Shortcuts app
- **WHEN** the user opens the Shortcuts app
- **THEN** Fernsy's actions are listed and can be used in shortcuts and automations

#### Scenario: What's on in Shortcuts
- **WHEN** the user runs Fernsy's "Was läuft gerade" action from the Shortcuts app
- **THEN** it answers with the current shows on the favourite channels and shows them as a list

### Requirement: Onscreen channel for actions
The player SHALL expose the playing channel as the onscreen entity, and the record action
without a channel SHALL record the show on now on that channel with the app's padding and
stream-limit rules and answer with the result.

#### Scenario: Record from the Shortcuts app
- **WHEN** the player shows Das Erste and the user runs Fernsy's "Aufnehmen" action without a channel
- **THEN** the current show on Das Erste is scheduled and the action says from when to when it records

### Requirement: Siri AI schemas
Fernsy SHALL adopt the `.system.open` schema with a channel as target, so asking Siri to open a
channel in Fernsy plays it (with the stream-limit rules), and the `.system.searchInApp` schema,
so asking Siri to search in Fernsy opens the library window with the search filled in.

#### Scenario: Opening a channel
- **WHEN** the user tells Siri "Öffne ZDF in Fernsy"
- **THEN** Fernsy plays ZDF

#### Scenario: Searching in Fernsy
- **WHEN** the user tells Siri "Suche Tatort in Fernsy"
- **THEN** Fernsy's library window shows the search results for "Tatort"
