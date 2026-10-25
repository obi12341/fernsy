# Proposal

## Why

Users want to control Fernsy by voice: switch channels, ask what is on, find a show, record
what they are watching. Siri reaches apps through App Intents. macOS 27's Siri AI understands
free conversation only for apps in Apple's schema domains (audio, calendar, mail, photos, …);
there is no video or TV domain, so Fernsy cannot join that. App Shortcuts, indexed app
entities and onscreen context do work for any app: fixed German and English phrases with
Fernsy's name and a channel or show as parameter, plus "this" for what the player shows. The
actions already exist with all their rules in the MCP tools.

## What Changes

- Fernsy declares App Intents and App Shortcuts (German and English phrases, the app name in
  each), available to Siri, Spotlight and the Shortcuts app:
  - "Schalte Fernsy auf <Sender>" / "Switch Fernsy to <channel>": plays a live channel.
  - "Was läuft gerade in Fernsy?" / "What's on in Fernsy?": now and next on the favourites,
    spoken and shown as a snippet.
  - "Wann kommt <Sendung> in Fernsy?" / "When is <show> on in Fernsy?": searches the guide of
    favourites and recently watched channels.
  - "Nimm das in Fernsy auf" / "Record this in Fernsy": records the show on the channel the
    player shows (or the given channel).
  - "Stopp Fernsy" / "Stop Fernsy": stops playback.
- Channels become indexed app entities (Spotlight semantic index), so Siri resolves spoken names
  like "das Zweite" or "Sky Formel 1"; favourites and recently watched are the suggested values.
- The player view is annotated with the channel entity, so "this" refers to what is on screen.
- The rules are the app's own, shared with the MCP server: hidden channels and adult content per
  Settings, IPTV films/series switches, and switching never ends a running recording (Siri says
  why instead).

Out of scope:
- Free conversational control without "Fernsy" in the sentence (needs an Apple video/TV schema
  domain that does not exist; audio schemas for radio would misrepresent the app).
- Jellyfin and IPTV films/series by voice, seeking, timeshift, volume, tracks.
- Siri on iPhone/HomePod controlling the Mac.

## Capabilities

### New Capabilities
- `siri`: the App Intents, App Shortcut phrases, channel entities and onscreen context Fernsy
  offers to Siri, Spotlight and Shortcuts, and the rules they follow.

### Modified Capabilities
<!-- none: the MCP tools keep their behavior; their logic moves to a shared layer -->

## Impact

- New `Fernsy/Intents/` (intents, `ChannelEntity`, `ShowEntity`, `FernsyShortcuts`
  AppShortcutsProvider, snippets).
- `Fernsy/MCP/MCPTools.swift`: the channel/guide/recording/playback logic moves into a shared
  `Fernsy/App/FernsyActions.swift` used by MCP and intents.
- `Fernsy/Views/PlayerScreen.swift` (entity on the player view), Spotlight indexing when the
  catalog changes (`AppModel`).
- `Fernsy/AppShortcuts.xcstrings` (phrases de/en), `Localizable.xcstrings`, `DEVELOPMENT.md`.
- AppIntents.framework is linked (removes the "no AppIntents.framework dependency" build note).
