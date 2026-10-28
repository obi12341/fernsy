# Tasks

## 1. Check first

- [x] 1.1 `LocalizationTests`: spelling check over all catalogs (design 3); it fails now and names the 17 strings.

## 2. Wording

- [x] 2.1 Apple TV: change the English literals per design 1 and move their catalog entries with the German values.
- [x] 2.2 Mac: the same for its three texts.
- [x] 2.3 UI tests that find tabs or buttons by English label ("Films") use the new wording.

## 3. Verification

- [x] 3.1 `scripts/test.sh` green (the spelling check passes), Mac build and full Apple TV UI suite green.
- [x] 3.2 Apple TV simulator in English: screenshot of the tab bar ("Movies") and a channel's menu ("Favorite").
- [x] 3.3 `tvos-jellyfin-overview` worktree: its new strings in US wording before it merges.
