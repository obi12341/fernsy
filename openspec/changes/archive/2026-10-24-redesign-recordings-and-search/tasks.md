# Tasks

## 1. Recordings

- [x] 1.1 `RecordingRow`: times side by side, outcome line with symbol, text and cause, `ProgressBar`, size in the second line. Verify: a demo run with a failed test recording (`IPTV_TESTRECORD` + `IPTV_TESTNODATA=offline:600`) and a scheduled one (`IPTV_TESTRECORD` in the future) → `IPTV_SCENE=recordings` screenshot.
- [x] 1.2 Permanent footer note. Verify: same screenshot.

## 2. Search

- [x] 2.1 Group order: channels, films, series, Jellyfin films, Jellyfin series, recordings. Verify: `IPTV_TESTSEARCH=Test` with a test recording; the recordings group comes last (screenshot).

## 3. Localization and verification

- [x] 3.1 Strings (de + en), with no stale keys. Debug/Release builds. `openspec validate redesign-recordings-and-search --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
