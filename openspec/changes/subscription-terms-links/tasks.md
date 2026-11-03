# Tasks

## 1. Shared terms

- [x] 1.1 `CloudTerms` in FernsyCore: renewal sentence (App Store and DMG), Terms URL (Apple standard EULA; fernsy.app terms for `DIRECT_DISTRIBUTION`), privacy URL by language, period text from the product ("1 month"); German strings; unit tests for URLs and texts per language and channel

## 2. Offers

- [x] 2.1 iOS: Settings › Fernsy Cloud and the assistant sheet show name · length · price, the renewal sentence and the two links
- [x] 2.2 Apple TV: settings and assistant overlay show the same with the two addresses as text
- [x] 2.3 Mac: `CloudEnableSheet` (App Store and DMG text) and the assistant window show the same with links
- [x] 2.4 UI tests: iOS (`IPTV_TAB=settings IPTV_SETTINGS=cloud`, `IPTV_CLOUD=http://127.0.0.1:9`) and Apple TV settings find both links/addresses; screenshots in both languages checked by eye; `scripts/vm.sh scripts/test.sh`

## 3. Store texts and release

- [x] 3.1 `docs/app-store.md`: subscription block with both links at the end of every description (iOS, tvOS, Mac; German and English); `python3 scripts/check-store-texts.py`
- [ ] 3.2 Archive, merge into `main`, push; the user tags `v2.3.1`; CI uploads the builds
- [ ] 3.3 App Store Connect: descriptions updated, versions 2.3.1 for iOS (with subscription and group) and tvOS submitted; the 2.3.0 versions replaced
