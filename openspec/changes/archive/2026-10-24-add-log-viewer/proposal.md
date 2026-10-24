# Proposal

## Why

When a stream stalls, a recording fails or Jellyfin refuses to play, the user has no way to
see what happened. The app store build writes no log at all. About 90 `debugLog` calls
(streaming, reconnects, tuner, timeshift, recordings, catalog, EPG, Jellyfin, PiP) exist,
but only in debug builds and only on stderr. A log the user can open from the menu makes
problems understandable and lets them send details along with a support request.

## What Changes

- New app-wide log (`AppLog`) that every build writes. It has a time, a level (info,
  warning, error, detail) and a category (player, network, tuner, timeshift, recordings,
  catalog, program guide, Jellyfin, PiP, app).
- The useful existing `debugLog` messages become `AppLog` entries in all builds.
  Per-second statistics and timing go to level "detail". Test hooks (`[test] …`) stay
  debug-only.
- Missing events are added at info, warning or error level: playback start and end (channel,
  film, episode, Jellyfin item), playback errors shown to the user, and sign-in or catalog
  failures.
- Credentials never reach the log. The Xtream username and password, Jellyfin tokens and
  `password=` or `api_key=` parameters are replaced by "•••" before an entry is stored.
- The log is kept in memory and in a file in the app's Caches folder. It holds the current
  and the previous app run, so a crash or a quit does not lose it, and it has a size limit.
- New log window "Protokoll" (EN "Log"), opened from the main menu Fenster › Protokoll
  (⌥⌘L). It offers:
  - a live list (newest at the bottom, follows new entries)
  - filters for level and category
  - a text search
  - switching between the current and the previous run
  - "Kopieren" (selection or all)
  - "Sichern …" (save as a text file)
  - "Leeren"
- Debug builds still write every entry to stderr as well, so existing debugging and the
  test runs keep working.

Out of scope:
- Sending logs anywhere (no upload, no analytics, no crash reporter).
- FFmpeg's own `av_log` output.
- A log entry in the menu bar item.
- Logging of private data beyond what is needed (no full URLs with credentials, no
  Jellyfin user data).

## Capabilities

### New Capabilities

- `app-log`: the app's own event log, what it records, how it is kept and protected, and
  the window that shows it.

### Modified Capabilities

(none)

## Impact

- New `Fernsy/App/AppLog.swift`: store, file persistence, redaction and the stderr mirror
  in DEBUG.
- New `Fernsy/Views/LogView.swift`: the log window.
- `Fernsy/App/FernsyApp.swift`: a new `Window("Protokoll", id: "log")` and a menu command.
- `debugLog` call sites in Player, Recording, Jellyfin, Xtream/EPG, App and Views move to
  `AppLog` with a category and a level.
- `Config/Fernsy.entitlements`: `com.apple.security.files.user-selected.read-write` for
  "Sichern …". This needs a short App Review note.
- `Fernsy/Localizable.xcstrings`: new UI texts. Log messages themselves stay in English and
  are not localized.
- README: the log and its file location.
