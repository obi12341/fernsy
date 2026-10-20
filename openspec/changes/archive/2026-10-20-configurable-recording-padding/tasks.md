# Tasks

## 1. Recorder

- [x] 1.1 Register 10/10 minute defaults and add `followsPaddingSettings` (decoded as `true` when missing; `false` for record-now without EPG and explicit padding); verify an old `recordings.json` still loads
- [x] 1.2 Re-apply padding to scheduled, settings-following recordings when the settings change; verify with `IPTV_TESTRECORD` plus a scheduled guide entry that only the guide entry changes and a running recording keeps its window

## 2. Settings and list

- [x] 2.1 Replace the padding Pickers with Stepper + number field clamped to 0…60; verify typing 90 shows 60 and −5 shows 0
- [x] 2.2 Show the recording window in Recordings rows when padding is not zero; verify a 20:15–21:45 entry with 10/10 shows "20:05 – 21:55" (screenshot via `IPTV_SCENE=recordings`)
- [x] 2.3 Translate new strings (xcstringstool sync, no untranslated keys)

## 3. Integration

- [x] 3.1 Record a demo show with custom padding (e.g. 1/1 min on a short entry) and verify the file's duration with the TS probe matches show length + padding

## Workflow follow-up

- Archive the change after review.
