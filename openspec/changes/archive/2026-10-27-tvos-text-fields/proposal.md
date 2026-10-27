# Proposal

## Why

On Apple TV the text fields draw two shapes on top of each other: the design's card with its
label, and inside it tvOS' own field platter, which turns white on focus. `.textFieldStyle(.plain)`
does not remove that platter on tvOS, so the sign-in forms show a white bar inside a light card and
the search fields show a bare white bar. The fields should look like the Claude Design screens.

## What Changes

- Every text entry in the Apple TV app is drawn as the design's field: on the sign-in forms a card
  with a small label over the value (password as dots, placeholder when empty) that lifts and turns
  light on focus; on search the design's hint line and the categories' search capsule. No system
  field platter is visible.
- Selecting such a field opens tvOS' text entry (on-screen keyboard, dictation, and the
  notification for typing on a nearby iPhone), as today; the value shows in the field after
  returning.
- Affected: the IPTV sign-in form, the Jellyfin sign-in form, the search field under Search's
  letter row, and the search field in All Categories.
- The UI tests that type into these fields follow the new elements.

Out of scope:
- The search letter row and its behavior (unchanged).
- Any change to what the forms ask for, validation, keychain storage or the demo button.
- A custom on-screen keyboard for the sign-in forms (rejected in tvos-live, design H).
- The Mac app.

## Capabilities

### New Capabilities

### Modified Capabilities
- `apple-tv`: a requirement for how text fields look and are entered on Apple TV.

## Impact

- `FernsyTV/Screens/SignInScreen.swift` (`FormField`, both forms),
  `FernsyTV/Screens/JellyfinSearchScreens.swift`, `FernsyTV/Screens/AllCategoriesScreen.swift`;
  a shared text-entry component under `FernsyTV/`.
- UI tests `SignInUITests`, `JellyfinSignInUITests`, `SearchUITests` and any test typing into the
  categories search.
- German strings in the TV string catalog if labels or placeholders change.
