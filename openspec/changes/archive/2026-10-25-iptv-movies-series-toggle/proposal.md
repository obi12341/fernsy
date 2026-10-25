# Proposal

## Why

Many IPTV users also run Jellyfin and want their films and series from there, not from the
IPTV provider. Today the provider's Movies and Series always appear in the sidebar and in the
search, so a search for a film shows the provider's copy next to (and above) the Jellyfin
one, and Fernsy downloads the provider's often large film and series catalogs on every refresh.

## What Changes

- Settings › Accounts › IPTV gets two switches, "Filme" and "Serien" (both on by default).
- A switched-off kind disappears everywhere for the IPTV account: its sidebar section, its
  hits in the search, its group under Favorites.
- A switched-off kind is no longer downloaded during catalog refreshes, and its cached
  catalog is removed. Switching it on again downloads it at once.
- Favorites, watched marks and resume positions of that kind are kept, so they return when
  the kind is switched on again.
- If the open section is switched off, the library shows Live TV.
- Debug switches `IPTV_SHOWMOVIES=0|1` and `IPTV_SHOWSERIES=0|1` set both switches in memory
  for one run.

Out of scope:
- Jellyfin films and series (Jellyfin has its own account and stays as it is).
- Hiding live TV, single film or series categories (category hiding already exists), or
  recordings.
- A per-account setting for several IPTV accounts (Fernsy has one IPTV account).
- Changing the sign-in screen's description of the IPTV account.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `catalog`: new requirement for switching the IPTV account's films and series off; the
  sidebar requirement lists Movies and Series only while they are on.
- `search`: the exclusions requirement also leaves out switched-off films and series.

## Impact

- `Fernsy/App/AppModel.swift`: two persisted settings, the catalog refresh and cache skip
  switched-off sections, `LibrarySection.iptv` becomes dependent on them, debug switches.
- `Fernsy/Views/LoginView.swift` (`AccountsSettings`): the two switches.
- `Fernsy/Views/LibraryView.swift`: sidebar list, Favorites rows, falling back to Live TV.
- Search (`SearchResultsView`/`SearchIndex`) and Favorites follow from the emptied catalogs;
  checked, not necessarily changed.
- `Fernsy/Localizable.xcstrings`, `DEVELOPMENT.md` (debug switches).
