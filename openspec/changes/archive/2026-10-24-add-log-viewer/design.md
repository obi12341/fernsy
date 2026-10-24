# Design

## Context

Logging exists only as `debugLog(_:)` in `PlayerEngine.swift`. It is compiled into DEBUG
builds only and writes "<seconds since start> <message>" to stderr. Callers use a
`[category]` prefix by convention (player, http, tuner, timeshift, recording, catalog, epg,
jellyfin, pip, search, tracks, zap, fs, test). Callers include demux and network threads, so
a log must accept entries from any thread. The app is sandboxed and has no file access
outside its container and `~/Movies`. User-facing error texts are German (localized). The
existing log texts are English.

## Goals / Non-Goals

**Goals:**
- One log for all builds that is cheap to call from any thread.
- No credentials in the log, ever.
- A window that makes the log readable and easy to hand over for support.

**Non-Goals:**
- Remote logging, crash reports, analytics.
- FFmpeg `av_log` output.
- Localized log messages.

## Decisions

### 1. `AppLog`: an in-memory ring plus a file, thread-safe

`AppLog` is a `final class` singleton, `@unchecked Sendable`, protected by an `NSLock`.

- **Entry:** `{ date, level, category, message }`.
- **Calls:** `AppLog.info(.player, "…")`, `.warning`, `.error` and `.detail` can be called
  from any thread.
- **Memory:** a ring of the last 20,000 entries.
- **File:** writes are appended in batches on a serial utility queue to
  `Caches/Fernsy/logs/current.log`, one line per entry (ISO 8601 time, level, category,
  message, tab-separated; newlines in messages escaped).
- **Size limit:** above 4 MB, the file is rewritten with its newest half.
- **Launch:** an existing `current.log` becomes `previous.log`.

The window observes a `@MainActor` `LogModel`. It takes new entries from `AppLog` at most 4
times per second, so a burst of entries on a background thread does not flood the main
thread.

`debugLog` stays for test hooks (`[test] …`) and stays DEBUG-only. In DEBUG, `AppLog` also
writes each entry to stderr in the old format, so test runs and log greps keep working.

Rejected: `os.Logger` with `OSLogStore`. The store only reads the current process
(`.currentProcessIdentifier`), so the previous run, which matters most after a crash or a
quit, would be lost. Private values are redacted by the system in a way the app cannot
control for its own viewer.

Rejected: memory only. A crash or quit loses the log right when it is needed.

### 2. Redaction when an entry is stored

Before an entry is stored, `AppLog` applies these replacements:

- Regex on the query parameters `username=`, `password=`, `api_key=` and `token=`: the
  value becomes `•••`.
- Xtream path credentials: `/(live|movie|series|timeshift)/<user>/<pass>/` becomes
  `/$1/•••/•••/`.
- Registered secrets, as literal text: the current Xtream password and the Jellyfin access
  token. `AppModel` and `JellyfinStore` register them on sign-in and remove them on
  sign-out. Only values of at least 4 characters are replaced.

The username is not replaced as plain text, because a short username like "demo" also
appears in host names. It is covered in queries and Xtream paths.

### 3. Levels and categories

- **Levels:** `error` for something that failed for the user (playback error, recording
  failed, sign-in failed). `warning` for something the app recovered from or worked around
  (reconnect, transcode fallback, timeshift off). `info` for normal milestones (playback
  started or ended, recording started or finished, catalog loaded). `detail` for frequent
  or technical data (stats, timing, subtitles, PiP geometry, zap keys).
- **Categories:** app, player, network, tuner, timeshift, recordings, catalog, guide,
  jellyfin, pip. The `[prefix]` in the existing messages maps to them (http becomes
  network, epg becomes guide; search, tracks, zap and fs become player or app as `detail`).
- **Prefix:** the message text drops the `[prefix]`.

### 4. Log window

The log window is `Window("Protokoll", id: "log")`. The command "Protokoll" (⌥⌘L) sits in
the Window menu (`CommandGroup(before: .windowList)`).

- **List:** a `Table` with time (HH:mm:ss.SSS), level (symbol and colour), category and
  message (monospaced, selectable rows).
- **Toolbar:** a level picker (Errors, Warnings and up, Info and up, All incl. details;
  the default is Info and up), a category menu (All or one), a search field, a run picker
  (Current or Previous), Copy, Save … and Clear.
- **Following:** the list scrolls to new entries while it is at the bottom.
- **Copy and Save:** both take the selected rows if any, otherwise all filtered rows.
- **Save:** uses `NSSavePanel`. It needs `com.apple.security.files.user-selected.read-write`.
  Review note: "Saves the app's own diagnostic log where the user chooses."
- **Clear:** empties the current run (memory and file).

Rejected: putting the viewer in Settings. It is a tool window the user keeps open next to
the player while reproducing a problem.

Rejected: Copy only, without Save. Copying thousands of lines through the clipboard is
clumsy for support mails.

Rejected: revealing the container's log file in Finder. The path is deep inside
`~/Library/Containers` and confusing for users.

### 5. Messages stay English

Log messages are not localized. They are for diagnosis and support, and one language
keeps them searchable. Error texts that came from a localized `PlayerError` appear as
shown to the user.

## Risks / Trade-offs

- Logging in hot paths (demux) could cost time. Only events are logged, never per packet,
  and appending is a lock plus an array write. File I/O happens off-thread in batches.
- Redaction relies on known patterns and registered secrets. A provider-specific URL format
  could slip through. The path and query rules cover the Xtream and Jellyfin formats Fernsy
  builds itself.
- Channel and show names appear in the log. This is accepted, because the log stays on the
  Mac unless the user saves or copies it.
