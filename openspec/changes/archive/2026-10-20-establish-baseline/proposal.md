# Proposal

## Why

Fernsy 1.0 was built and shipped without written specs; its behavior and the reasons behind
it exist only in code, commit history and past chat sessions. Capturing the shipped behavior
as OpenSpec capabilities gives future changes a baseline to diff against and keeps earlier
decisions (licensing, single-stream handling, signing, review setup) traceable.

## What Changes

- Document the behavior of Fernsy 1.0 as it ships today, one capability per area.
- Record the key technical and product decisions taken so far, with rationale, in design.md.
- No code changes.

Out of scope: timeshift, recordings and the menu bar item (separate change
`add-timeshift-and-recordings`); anything not yet built.

## Capabilities

### New Capabilities
- `account`: signing in to an Xtream Codes provider, storing and removing credentials.
- `catalog`: live, movie and series catalogs with categories, search, favorites and caching.
- `live-tv`: channel list, now/next information, starting channels and zapping.
- `program-guide`: the TV guide grid with program data loading and caching.
- `playback`: the player window for live and on-demand media, decoding, tracks, resume, reconnects.
- `localization`: German and English user interface.
- `distribution`: Mac App Store build, DMG build, signing and third-party licensing.
- `demo-server`: the public demo Xtream server used for App Review and testing.
- `website`: the product website with support and legal pages.

### Modified Capabilities

None (no specs existed before).

## Impact

Documentation only: `openspec/specs/**` after archive.
