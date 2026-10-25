# Tasks

## 1. Schema intents

- [x] 1.1 Add `OpenChannelIntent` (`.system.open`, target `ChannelEntity`) using `IntentActions.play`, and `SearchFernsyIntent` (`.system.searchInApp`) setting `AppModel.requestedSearch`, applied by `LibraryView` (opens the library window when none is open); `IPTV_TESTINTENT` steps `open:<id>` and `search:<text>`; verify on the demo server: `open:102` plays Channel South (log), `search:cooking` fills the search (window screenshot shows results), and with all windows closed (`IPTV_TESTCLOSE=3`) the search opens the library window
- [x] 1.2 Verify the built app's `Metadata.appintents` lists both intents with their schemas (`system.open`, `system.searchInApp`); sync `Localizable.xcstrings` with English; update `DEVELOPMENT.md`

## 2. Integration

- [x] 2.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`
- [x] 2.2 Spoken check with the nightly by the user ("Öffne ZDF in Fernsy", "Suche Tatort in Fernsy"); not blocking — Left to the user with the nightly; the intents' effect is verified in 1.1 (open plays, search fills the library search, both also from menu bar mode)
