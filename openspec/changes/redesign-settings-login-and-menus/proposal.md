# Proposal

## Why

The remaining surfaces need to match the redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f): sign-in, settings, the menu
bar item and the log window. The source is `Anmeldung.dc.html`, `Einstellungen.dc.html`,
`Menueleiste.dc.html` and `Protokoll.dc.html`. The source also makes youth protection
transparent and warns before quitting stops a recording.

## What Changes

- **Sign-in**:
  - The account type is the first decision: two cards (IPTV, Jellyfin), each with a short
    explanation of what the source provides.
  - Errors appear directly below the affected fields, which get a red outline.
  - The privacy note "Fernsy sammelt keine Daten" stays visible in the footer.
- **Settings**:
  - A classic settings window with tabs in the toolbar and grouped forms.
  - "Jugendschutz" lists the categories Fernsy detected as adult content, with their raw
    names as the source.
  - The menu bar item setting moves to the recordings tab.
- **Menu bar**:
  - The TV symbol gets a red dot during a recording.
  - The menu shows running recordings with end time and "Beenden", and the next scheduled
    one.
  - It warns that "Fernsy beenden" stops the running recording.
- **Log window**:
  - Levels shown with colour, symbol and text.
  - Run picker, level filter and search in the toolbar; Copy, Save and Clear beside them.
  - Times in monospace with milliseconds.

Out of scope:
- Account handling, settings semantics and logging behaviour, which stay as specified.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `account`: account type cards, inline field errors and the privacy footer on sign-in.
- `jellyfin-account`: the account type choice shares the new sign-in screen.
- `catalog`: the youth protection settings list the detected adult categories.
- `menu-bar`: the red dot on the symbol, and the warning that quitting stops a recording.
- `app-log`: the toolbar layout of the log window.

## Impact

- `LoginView.swift` (sign-in, `SettingsView`), `MenuBar.swift`, `LogView.swift`.
- `AppModel`: the list of detected adult categories for display.
- Depends on `redesign-foundation`.
