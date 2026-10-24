# Tasks

## 1. Tokens

- [x] 1.1 Add `AccentColor` (#6C65F0 any, #958FFF dark) to `Assets.xcassets` and set `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` in Debug and Release. Verify: buttons and selections are violet in a debug run (screenshot of the Fernsy window).
- [x] 1.2 `Fernsy/Views/Design/Theme.swift` with `record`, `warning`, `logoTile`, `logoTileLight` and `tagBorder`, each per appearance. Verify: build.

## 2. Components

- [x] 2.1 `ImagePipeline`: measure the logo tone (transparency share, mean luminance of opaque pixels) on the 16×16 thumbnail and cache it with the image. Add `tone(for:)`. Verify: a debug self-test `IPTV_LOGOTONETEST=1` classifies generated white-on-clear, black-on-clear and opaque samples correctly.
- [x] 2.2 `LogoTile(url:name:width:)`: 13:8, inset logo, graphite or light tile by tone, initials fallback. Verify: initials "KS" for "Kanal Süd", and "N1" for "Nordlicht 1" (self-test).
- [x] 2.3 `StatusBadge(kind:)` with all kinds (symbol + text). Verify: build. Used in 3.1.
- [x] 2.4 `PosterCard`: title placeholder on a neutral surface (also on load failure), rating as "★ 7,3" capsule on the poster, year below the title. Verify: a demo film without a poster shows its title (screenshot).

## 3. Adoption

- [x] 3.1 Sidebar: recordings badge "n läuft" while recordings run, the Jellyfin header with a status dot and server name or "Offline", and the footer with the account host, "Gültig bis" and "Stand". Verify: a demo run with `IPTV_TESTRECORD=101:5:60` shows the badge (screenshot).
- [x] 3.2 `ChannelRow` and the guide's channel column use `LogoTile`. Verify: a demo run shows logos on tiles in the list and guide, dark and light (screenshots in both appearances via the debug switch `IPTV_APPEARANCE=light|dark`).

## 4. Localization and verification

- [x] 4.1 New strings ("läuft", "Offline") in `Localizable.xcstrings` (de + en) via `xcstringstool sync`, with no stale keys. Verify: build without missing translations.
- [x] 4.2 Debug and Release builds compile, and `openspec validate --all --strict` passes for this change (the other redesign changes are still proposals only).

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
