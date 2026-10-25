# Proposal

## Why

There is a 44-second promo video in German ("Fernsy – die Mac-Odyssee") and English
("Fernsy – the Mac odyssey") that shows what Fernsy is for better than a still image of the
player. Each home page should show the video in its language in the hero, in place of the
player image. It must not start or download on its own: visitors start it with
Play.

## What Changes

- The German home page (`website/index.html`) shows the German video in the hero frame
  instead of `assets/player-live.webp`; the English home page (`website/en/index.html`)
  shows the English video instead of `assets/en-player-live.webp`.
- Before playback, a still frame from the video is shown as a poster with a large play
  button over it. Nothing plays and the video file is not loaded until the visitor clicks
  Play (`preload="none"`, no `autoplay`).
- The source files (`~/Downloads/fernsy-die-mac-odyssee.mp4` and
  `~/Downloads/fernsy-the-mac-odyssey.mp4`, each 1920×1080, H.264/AAC, 40 MB) are
  re-encoded once, locally, to smaller H.264/AAC MP4s with fast start and committed as
  `website/assets/fernsy-video.mp4` and `en-fernsy-video.mp4`, each with a poster
  (`fernsy-video-poster.jpg`, `en-fernsy-video-poster.jpg`, see design).
- Without JavaScript, the video shows with the browser's own controls, so it can still be
  played.

Out of scope:
- Captions or subtitles for the video.
- Autoplay, looping or a muted background video.
- External video hosting (YouTube, Vimeo, a CDN) or GitHub Release assets.
- The other sections of the home page, including the second player image in "New in Fernsy"
  and the Big Buck Bunny credit in the footer (that image still uses the mockup).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `website`: the home page requirement changes from "a hero image of the player" to a hero
  video in the page's language that only plays after the visitor clicks Play.

## Impact

- `website/index.html`, `website/en/index.html`: hero markup and the inline script.
- `website/style.css`: styles for the video, the poster and the play button.
- `website/assets/`: two new MP4s (target 10–15 MB each) and two poster images. The repo and every Pages
  deployment grow by that size; GitHub's 100 MB per-file limit is far away.
- `.github/workflows/pages.yml` needs no change: it publishes everything under `website/`.
- No app code, no FFmpeg, no entitlements involved.
