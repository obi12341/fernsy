# Design

## Context

See proposal.md for the test result. Siri AI matches requests to schema intents; App Shortcut
phrases are not used by voice on macOS 27. The `.system` domain offers `open` (an `OpenIntent`
with `target: <AppEntity>`) and `searchInApp` (a `ShowInAppSearchResultsIntent` with
`criteria: StringSearchCriteria` and `searchScopes`). `ChannelEntity` is already in the semantic
index, so Siri can resolve channel names for `open`.

## Goals / Non-Goals

**Goals:**
- Voice: switching channels and searching Fernsy, the two things a schema covers.

**Non-Goals:**
- Reproducing MCP features by voice.

## Decisions

- **`OpenChannelIntent` = `@AppIntent(schema: .system.open)`, target `ChannelEntity`**; perform
  calls the existing `IntentActions.play` (recording check, player window). Opening a live
  channel means watching it, so `open` is the honest mapping. Rejected: the audio domain's
  `playAudio` with `liveRadioStation` (misrepresents a TV app, likely review trouble).
- **`SearchFernsyIntent` = `@AppIntent(schema: .system.searchInApp)`**, `searchScopes:
  [.general]`; perform sets `AppModel.requestedSearch` to the criteria's term; `LibraryView`
  applies it to its toolbar search (the same state `IPTV_TESTSEARCH` drives) and clears the
  request; if no library window is open (menu bar mode), it is opened through the stored
  `openWindow` (as the player window is). Rejected: searching the guide here (the toolbar search
  covers names, not programmes; guide search stays with MCP).
- **Spec honesty**: the phrases requirement now names Shortcuts and Spotlight as where the App
  Shortcuts work.

## Risks / Trade-offs

- [Siri AI may still route some phrasings elsewhere] → the user checks "Öffne ZDF in Fernsy"
  and "Suche Tatort in Fernsy" with the nightly; the debug hook covers the intents' effect.
