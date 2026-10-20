# Proposal

## Why

Program data from IPTV providers is often a few minutes off, so recordings planned from the
guide miss the beginning or the end of a show. The current padding defaults (2 min before,
10 min after) are too tight for this, and the settings only offer a few fixed values. The
user wants 10 minutes on both sides by default and to choose the padding freely.

## What Changes

- Default padding for recordings planned from program data becomes 10 minutes before and
  10 minutes after the show.
- Settings let the user set both paddings to any whole number of minutes from 0 to 60
  (instead of a fixed list).
- Changing the padding also applies to scheduled recordings that have not started yet.
- The recordings list shows the actual recording window (show time plus padding).

Out of scope: per-recording padding (editing a single recording), padding for recordings
without program data (player "record now" without EPG keeps recording two hours from the
press), automatic detection of show boundaries.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `recordings`: "Padding" changes defaults, range and when settings take effect; the
  recordings list shows the padded window.

## Impact

- `Fernsy/Recording/Recorder.swift` (defaults, re-applying padding to scheduled entries),
  `Fernsy/Views/LoginView.swift` (settings controls), `Fernsy/Views/RecordingsView.swift`
  (window display), `Localizable.xcstrings`.
- Users who never changed the padding get the new defaults; explicitly chosen values stay.
- More overlap between back-to-back recordings on different channels, so the
  connection-conflict prompt appears more often on single-stream accounts.
