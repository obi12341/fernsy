# Tasks

## 1. Parser

- [x] 1.1 `Fernsy/Xtream/ChannelName.swift`: `ChannelName.parse` (decoration, country prefix forms with a known-code list, quality suffix, fallback). Verify: `IPTV_NAMETEST=1` passes all spec examples and the edge cases from design §1.
- [x] 1.2 `LiveChannel` and `XCategory` store the parse result (`displayName`, `country`, `quality`, `rawName`); the search key stays raw. Verify: build. Searching "ZDF" and "DE: ZDF" both find the channel (debug `IPTV_TESTSEARCH`).

## 2. Display

- [x] 2.1 `NameTag` in `Fernsy/Views/Design/`. `ChannelRow`, the guide's channel column and the category column show the cleaned names with tags. Verify: screenshot of the list and guide (demo "Northern Light 1 HD" → "Northern Light 1" + "HD").
- [x] 2.2 Player title, zap banner, menu bar and the recording's `channelName` use the cleaned name. The recording file name is "Name (CC) – Title (…).ts". Verify: `IPTV_TESTRECORD` on a demo channel; the file name and the list entry use the cleaned name.

## 3. Live TV entries and info

- [x] 3.1 Pinned "Favoriten" and "Zuletzt gesehen" in the Live TV category column. `recentChannels` (20, newest first, `UserDefaults` "live.recent") is updated on play; the list and guide follow. Verify: play two demo channels via `IPTV_TESTSWITCH`, select "Zuletzt gesehen" (`IPTV_SCENE=live:__recent`); the order is newest first (screenshot).
- [x] 3.2 "Senderinfo …" (⌘I) in the channel context menu and for the selected channel: a sheet with the raw name, number, raw category, EPG id, archive and Copy. Verify: build; a debug switch `IPTV_TESTINFO=<channel id>` opens the sheet (screenshot).

## 4. Localization and verification

- [x] 4.1 New strings in `Localizable.xcstrings` (de + en) via `xcstringstool sync`, with no stale keys. README lists `IPTV_NAMETEST` and `IPTV_TESTINFO`. Verify: build without missing translations.
- [x] 4.2 Debug and Release builds compile. `openspec validate channel-names-and-countries --strict` and `openspec validate --specs --strict` pass.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees (after `redesign-foundation`).
