# Design

## Context

- `tvos-foundation` built `TVModel`, the placeholder screens in `FernsyTV/Screens/` (screen
  slots, see DEVELOPMENT.md › Apple TV), `TVVideoSurface`, the debug MCP on 52325,
  `scripts/tv-run.sh` and `scripts/tv-uitest.sh`. Playback, tuner pool and timeshift are in
  `FernsyPlayer`; provider, guide, names and history logic in `FernsyCore`.
- The design is `AppleTV.dc.html` in the Claude Design project "Fernsy Redesign", 1920×1080,
  one prop `screen`. This change builds the screens `login`, `login2`, `live`, `kategorien`,
  `guide`, `player`, `zap`, `aufnahmen` and `einstellungen`; `tvos-library` builds `home`,
  `filme`, `film`, `jellyfin`, `serie` and `suche`. Colors, type sizes and spacing are taken
  from the design file, not guessed from screenshots.
- On the Mac, favourites, recent channels, pins and visibility live in the app (`AppModel`,
  `ChannelVisibility.swift`), the recorder in `Fernsy/Recording/Recorder.swift` (imports
  AppKit), its plan and gap logic already in `FernsyCore` (`RecordingPlan`, `GapTracker`).
- tvOS suspends an app shortly after it leaves the foreground, and the Apple TV sleeps after
  the idle time set in its settings. There is no lasting local storage: only Caches and tmp,
  which tvOS may purge.

## Goals / Non-Goals

Goals: the designed live screens, recordings that are honest about tvOS' limits, and the
Mac's live behavior (favourites, hiding, pins, zapping, single-stream rules) from shared code.

Non-goals: pixel-perfect identity with the HTML (tvOS' focus engine, fonts and motion decide
some details), new behavior on the Mac.

## Decisions

### A. Shared live state moves into `FernsyCore`

The rules and stored formats for favourites, recently watched channels, hidden categories and
channels, the adult-category detection and the zap order move from the Mac app into
`FernsyCore` with the same stored keys and files (so the Mac keeps its data). Both apps use
them; the Mac's views keep their behavior. Pinned categories are new: a small per-account file
(`pinned.json`, like `visibility.json`) in `FernsyCore`, used only by the Apple TV app for now.
Rejected: a second copy in `FernsyTV` (the rules, e.g. "channels of a hidden category are
hidden everywhere", would drift apart).

### B. The recorder moves into `FernsyPlayer`

`Recorder` is split: scheduling, padding, the stream-limit rules and the file writing
(via `TimeshiftWriter`'s muxer) go to `FernsyPlayer`; the Mac keeps its AppKit parts (Movies
folder, notifications, sleep prevention, Finder) behind a small platform protocol. Apple TV
implements that protocol with Caches/Recordings, `isIdleTimerDisabled` and its own list.
Rejected: a separate tvOS recorder (two implementations of the stream-limit rules; the Mac's
was hard-won, see the `recordings` spec).

### C. Recordings only while the app is open

A recording runs while Fernsy is in the foreground. During a recording the app sets
`UIApplication.isIdleTimerDisabled`, so the Apple TV does not sleep. When tvOS sends the app to
the background (Home button, another app) the recorder finishes the file at once and marks it
incomplete; a background task is used only to close the file. Scheduled recordings that ended
while the app was not running are marked missed at the next launch. Scheduling shows the hint
"Nimmt nur auf, solange Fernsy geöffnet ist." Rejected: recording in the background (tvOS does
not allow long-running background work for this); not recording at all (user decision
2026-10-26: record on Apple TV and accept the limits).

### D. Recordings in Caches

Recordings are written to `Caches/Recordings/<account>/`, with a small JSON index next to them.
At launch the index is checked against the files; entries whose file is gone are dropped
(tvOS purged it). Before a recording starts, free space is checked; below 2 GB it is refused
with a message. Rejected: Application Support (tvOS limits it and may refuse the app for
large data there; it is not meant for media).

### E. Preview in the Live TV pane shares the tuner

The pane's preview starts when focus has rested on a row for 1 s, muted, through the
`TunerPool` like the player, so clicking the row continues the same connection full screen. It
stops when focus leaves Live TV. With the account's stream limit reached (e.g. a recording of
another channel on a single-stream account), the pane shows logo and programme instead.
Rejected: starting a preview on every focus move (connection churn; some providers block
accounts that reconnect rapidly); no preview (the design shows one).

### F. Navigation with tvOS' `TabView`

The top tab bar is SwiftUI's `TabView` with tvOS' top tab style, styled to the design (pill,
search and gear as icon tabs). It gives the system focus behavior (up to the tab bar, Back to
the tab bar) for free. Rejected: a hand-made tab bar (focus and Back handling would have to be
rebuilt and still feel different from other Apple TV apps).

### G. Guide grid as a custom focusable layout

The guide is a lazily built grid: rows per channel, shows as focusable cells whose width is
their duration on the axis, a now line, and horizontal scrolling by time. Guide data comes from
`EPGStore`, loaded for the visible rows. Rejected: `LazyHGrid`/`List` (fixed cell sizes, no
duration-based widths).

### H. Text entry

The form uses system `TextField`/`SecureField`, which bring tvOS' keyboard and the iPhone
notification for typing without extra code. "Demo-Zugang testen" fills the demo server
credentials and signs in, in every build (useful for App Review on Apple TV). Rejected: a
custom on-screen keyboard here (search in `tvos-library` has one because the design shows it
inline).

### I. Long press menus

A long press on a row or tile opens a tvOS context menu (`contextMenu`) with the design's
entries. Rejected: a custom sheet (the context menu is what tvOS users expect for long press).

### J. Verification

Screens are checked against the design with simulator screenshots (`xcrun simctl io`) next to
the rendered design screens, on the demo server. The debug MCP gets `record`, `list_recordings`
and `cancel_recording`; the UI tests grow by sign-in with the demo button, zapping from the
strip, hiding a channel and scheduling a recording.

## Risks / Trade-offs

- [The user leaves the app and a scheduled recording is missed] → the scheduling hint, the
  missed state with its reason in Aufnahmen.
- [tvOS purges recordings to free space] → the index check at launch; the Aufnahmen screen
  explains that tvOS may remove recordings when space is short.
- [Simulator decodes in software] → picture and performance are checked on a real Apple TV
  before release (not part of this change).
- [Moving the recorder could change Mac recordings] → the Mac regression with
  `IPTV_TESTRECORD=101:5:60:0:0`, a single-stream run with `IPTV_MAXCONN=1`, and the existing
  recording tests.

## Migration Plan

The Mac's stored favourites, history, pins and visibility keep their keys and format, so
nothing is migrated. The Apple TV app has no data from earlier builds worth keeping.
