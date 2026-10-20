# Tasks

## 1. Setup

- [x] 1.1 Pick Jellyfin test items with several audio languages and forced/full subtitle tracks (a German-dubbed film with a German forced track, a film with English + German audio and both subtitle kinds, a series with ≥ 2 episodes, the episode with external subtitles) and back up their user data

## 2. Track model and chooser

- [x] 2.1 `MediaTrack` language/forced/default from FFmpeg (disposition, title) and Jellyfin streams (`IsForced`, `IsDefault`)
- [x] 2.2 `TrackPreferences` and `TrackChooser` with the rules from the design; unit-check the rules with a small debug self-test over sample track lists (`IPTV_TRACKSELFTEST=1` logs pass/fail for each rule)

## 3. Applying the choice

- [x] 3.1 `PlaybackSession` preselects audio and subtitles via the chooser before the first packet; verify with `JF_AUTOPLAY` + `IPTV_AUDIOLANG=en IPTV_SUBTITLES=de` on the English + German film (info: English audio, German subtitles shown)
- [x] 3.2 `JellyfinPlayback` chooses over Jellyfin streams (embedded + external) and passes the selection to direct play and transcode; verify `IPTV_SUBTITLES=forced` on the German-dubbed film shows only the forced track and on the external-subtitle episode with `IPTV_SUBTITLES=de` selects the external track
- [x] 3.3 IPTV live and VOD use the same preselection; verify a demo-server film and channel (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUDIOLANG=system`) still start with their audio track and subtitles off

## 4. Visible selection

- [x] 4.1 Audio and subtitle menus as inline pickers with checkmarks; filled subtitle icon while on; help texts with the current track; verify by screenshots of both open menus

## 5. Settings and series memory

- [x] 5.1 Settings section "Sprache & Untertitel" with both pickers and the debug overrides; verify by screenshot of the settings (German and English UI) without changing the stored values
- [x] 5.2 Series memory for IPTV and Jellyfin episodes from explicit menu choices; verify with `IPTV_TRACKSTORE=test` and `IPTV_TESTAUDIO`/`IPTV_TESTSUB` on episode 1 that episode 2 starts with the same languages, and that a film still uses the defaults

## 6. Finish

- [x] 6.1 Translations (xcstringstool sync, no untranslated keys), README note on the language settings and debug switches
- [x] 6.2 Restore the Jellyfin test items' user data and remove the `tracks.series.test` key; verify the user's own `tracks.*` settings are unchanged; log out test sessions, remove credentials and verify nothing secret is in the repository or logs

## Workflow follow-up

- Archive after the user's review, then merge `change/track-selection-and-language-defaults` into `main` with the user's OK.
