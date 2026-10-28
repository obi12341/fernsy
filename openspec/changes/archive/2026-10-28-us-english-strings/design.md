# Design

## Context

- SwiftUI uses the English literal as the catalog key (`Text("Films")`, `String(localized:)`), so
  changing the English text means renaming the key in the catalog; the German value moves with it.
- Found British spellings (2026-10-28): Apple TV "Films", "Films and Series", "Films · %@",
  "FILM", "Favourite", "Remove Favourite", "No favourites yet …", "Favourites, hidden channels
  and recordings …", "Loading programme …", "No programme information", "Your films and series
  appear …", "Your own library with films, series …", "Live TV, guide, films and series …",
  "Hidden categories and channels, favourites, …"; Mac "Films and series from your own server",
  "Live TV, guide, films and series from your provider", "Hidden categories and channels,
  favourites, …".
- `LocalizationTests.everyKeyHasGerman` already walks all six catalogs.

## Goals / Non-Goals

**Goals:**
- One English: US wording in both apps.
- A test that keeps it so.

**Non-Goals:**
- German wording; code identifiers, accessibility ids, file names.

## Decisions

1. **Wording table**, applied to the English literals and keys:
   Films → Movies, film → movie, FILM → MOVIE, Favourite(s) → Favorite(s),
   programme → program ("Loading program …", "No program information"), Cancelled → Canceled
   (FernsyPlayer, found by the check); German unchanged.

2. **Rename keys with their German value.** A script moves each catalog entry from the old key
   to the new one (keeping all localizations) and the code literal is changed in the same
   commit; no entry is left stale. Rejected: leaving old keys in the catalog (Xcode marks them
   stale and they hide which text is current).

3. **Spelling check in `LocalizationTests`.** A second test walks the same catalogs and fails on
   English keys matching a list of British forms (`\bfilms?\b`, `favourit`, `programme`,
   `colour`, `centre`, `catalogue`, `behaviour`, `cancelled`, `licence`), case-insensitive,
   naming the string. Rejected: a lint script outside the tests (one more thing to remember to
   run; the tests already run in CI).

4. **Unmerged changes follow the rule before they merge.** `tvos-jellyfin-overview` (worktree)
   gets "%lld movies", "Movies and Series" and the like; whichever merges second resolves the
   catalog with the US keys.

## Risks / Trade-offs

- [A word in a title or name matches the list, e.g. a channel called "Film"] → catalogs contain
  UI texts only, not content; an allow-list in the test covers an exception if one appears.
- [UI tests that find elements by English label] → updated in the same commit; identifiers are
  unchanged.
