# Proposal

## Why

The UI's source language is English with US spelling (localization spec), but the Apple TV app
says "Films", "Favourite" and "programme", and a few Mac texts say "films" and "favourites".
English-speaking users see a British-American mix ("Favorites" next to "Remove Favourite" on
Apple TV), and the App Store listing and screenshots inherit it. Nothing checks for it, so new
strings keep adding to it (the unmerged Jellyfin overview adds "%lld films").

## What Changes

- English source texts use US wording: "Movies" instead of "Films", "Favorite(s)" instead of
  "Favourite(s)", "program"/"guide" instead of "programme" (17 texts: 14 on Apple TV, 3 on the
  Mac). German translations stay as they are.
- The localization tests fail on British spellings in any catalog's English text, so it does
  not come back.
- The localization requirement names the Apple TV app too (it only spoke of macOS).

Out of scope: the German wording; identifiers in code and accessibility ids (they are not shown);
spec texts, which name the UI in German.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `localization`: "German and English UI" covers the Apple TV app and US wording explicitly, with a check.

## Impact

- `Fernsy/` and `FernsyTV/` views whose English literals change; both `Localizable.xcstrings`
  (keys renamed, German kept).
- `LocalizationTests` (FernsyCore) gains the spelling check.
- UI tests that find tabs by English label (`tabBars.buttons["Films"]` in LibraryUITests,
  VODSwitchUITests, JellyfinEdgesUITests).
- The unmerged `tvos-jellyfin-overview` gets US wording before it merges.
