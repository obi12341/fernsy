# Design

## Context

Fernsy has no App Intents today (the build notes "no AppIntents.framework dependency"). The MCP
server's `MCPTools` already implements the needed actions on the main actor with the app's rules:
visible channels (`filteredChannels`), guide loading with a time cap, scheduling through
`Recorder.schedule`, playback through `AppModel.play` with the `recordingsBlocking` check, and
`PlayerWindow` to show the player when no library window is open. Siri reaches non-schema apps
through App Shortcuts (phrases with the app name and entity/enum parameters), entities found via
their queries or the Spotlight semantic index (`IndexedEntity`), and onscreen context from views
annotated with entity identifiers.

## Goals / Non-Goals

**Goals:**
- One implementation of each action for MCP and Siri.
- Phrases that work in German and English without user setup.

**Non-Goals:**
- Schema-based Siri AI integration (no fitting domain), Jellyfin by voice.

## Decisions

- **Shared action layer `FernsyActions`** (`@MainActor`, results as small Swift structs with the
  data and a human sentence): visible channels and lookup, now/next for channels, guide search,
  schedule a show / record now, play channel with the recording check, stop. `MCPTools` maps its
  JSON onto these; intents map them onto dialogs and snippets.
  Rejected: intents calling the MCP layer through JSON (stringly typed, loses Swift types) and
  duplicating the logic (two places to keep the stream-limit and visibility rules in sync).
- **Entities**: `ChannelEntity` (id, name, category; `IndexedEntity` with the name and the
  delivered raw name as indexed keys; `EntityStringQuery` over visible channels by search key;
  `suggestedEntities` = favourites + recently watched, at most 50). `ShowEntity` (show id
  `<channel>:<start epoch>`, title, channel, start, end) returned by the search intent and
  accepted by a "record show" intent. The index is rebuilt (`CSSearchableIndex` via
  `indexAppEntities`) when channels, visibility or adult settings change, debounced, and cleared
  on sign-out.
- **Intents** (`openAppWhenRun` false; they run in the app process, which macOS launches if
  needed; `perform` is `@MainActor`):
  `PlayChannelIntent(channel)`, `WhatsOnIntent()`, `FindShowIntent(query)`,
  `RecordIntent(channel?)` (defaults to the onscreen/playing channel), `StopPlaybackIntent()`.
  Results: `ProvidesDialog` sentences in the user's language from `Localizable.xcstrings`;
  `WhatsOn` and `FindShow` add a SwiftUI snippet list. Errors are dialogs, not throws, so Siri
  speaks the reason (blocked by recording, not signed in, no programme data).
- **App Shortcuts** in `FernsyShortcuts: AppShortcutsProvider`, phrases with
  `\(.applicationName)` and `\(\.$channel)`; localized phrases in `AppShortcuts.xcstrings`
  (de, en). At most 10 shortcuts, each a few phrase variants.
- **Onscreen context**: the player view sets `.appEntityIdentifier(EntityIdentifier(for:
  ChannelEntity.self, identifier: id))` for live channels and donates `PlayChannelIntent` on
  every channel start (`IntentDonationManager`), which also teaches Siri the user's habits.
- **Not signed in / films off**: intents answer "Melde dich zuerst in Fernsy bei deinem
  IPTV-Konto an." and so on; nothing opens unexpectedly.

## Risks / Trade-offs

- [Siri voice cannot be tested here (no microphone input from the agent)] → every intent is
  driven by a debug hook (`IPTV_TESTINTENT=<intent>:<arg>`) calling `perform()` exactly as the
  system does, the metadata is checked in the built app (`Metadata.appintents`), and the user
  tries one spoken phrase with a nightly.
- [Phrase parameters are limited to suggested entities] → favourites and recently watched cover
  the common case; other channels work through the search intent's follow-up or Shortcuts.
- [Large catalogs (50,000 channels) in the semantic index] → index only visible live channels,
  in batches in the background; films/series are not indexed.
- [Debug builds register their intents too] → harmless (separate bundle path); the debug
  build's Spotlight entries are cleared on quit in DEBUG.
