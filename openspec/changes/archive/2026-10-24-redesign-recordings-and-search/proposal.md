# Proposal

## Why

Recordings and search already have the right content, but they look different from the
rest of the redesign. The source in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f), `Aufnahmen.dc.html` and `Suche.dc.html`,
adjusts them to the shared components and makes failures and channel hits more useful.

## What Changes

- **Recordings**:
  - Läuft, Geplant and Aufgenommen are sections of one list.
  - Scheduled recordings show the show time and the actual recording window side by side.
  - Failures show as text with their own symbol in the row ("fehlgeschlagen", "verpasst",
    "ausgelassen") plus the cause.
  - The note that Fernsy must stay open is a permanent footer.
  - The context menu offers Finder and Trash.
  - Running recordings keep the red progress; waiting ones show "Wartet auf den Sender …".
- **Search**:
  - Groups in the order Sender, Filme, Serien, Jellyfin-Filme, Jellyfin-Serien, Aufnahmen,
    each with a count and "Alle anzeigen".
  - Channel hits are rows with logo tile, tags and the current show, so they can be started
    directly.
  - Empty groups are left out.

Out of scope:
- Recording behaviour and search ranking, which stay as specified.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `recordings`: the presentation of the Recordings section (side-by-side windows, failure
  text with cause, footer note).
- `search`: group order and channel hits with now info.

## Impact

- `RecordingsView.swift`, `SearchResultsView.swift`.
- Depends on `redesign-foundation` and `channel-names-and-countries`.
