# Tasks

No IPTV stream or demo-server run is involved: this change only touches `website/`. Pages are
checked locally in headless Chrome only (file requests and video state read from the page); no
local web server is kept. Safari, Firefox and the iPhone are checked on www.fernsy.app after the
GitHub Pages deploy (see Workflow follow-up).

## 1. Branch and media files

- [x] 1.1 Create the branch `change/website-hero-video` from `main`; verify with `git branch --show-current`
- [x] 1.2 Copy `~/Downloads/fernsy-die-mac-odyssee.mp4` into a new, empty scratchpad folder and encode it with `avconvert --preset Preset1920x1080`; if the output is above 15 MB, encode with the Swift AVAssetWriter script from design.md §2 (H.264 High ≈2.5 Mbit/s, AAC 128 kbit/s, network-optimized); verify size 10–15 MB (`ls -l`), 1920×1080, H.264/AAC and duration ≈44 s (`mdls`)
- [x] 1.3 Play the encoded file full screen in QuickTime and ask the user to confirm that text in the code and app scenes is readable; raise the bitrate (max. ≈20 MB) if not, and record the final bitrate and size in design.md §2
- [x] 1.4 Extract candidate poster frames with `AVAssetImageGenerator` (Swift, scratchpad) at 1920×1080, show them to the user and let them pick one; verify the chosen frame is saved as `website/assets/fernsy-video-poster.webp` (or `.jpg` via `sips`, quality 80) under 250 KB
- [x] 1.5 Copy the final MP4 to `website/assets/fernsy-video.mp4`; verify `git status` shows only the two new asset files

## 2. Hero markup, script and styles (German home page)

- [x] 2.1 In `website/index.html`, replace the hero `<img>` with the `<div class="frame video">` block from design.md §1 (`controls`, `preload="none"`, `playsinline`, poster, `<source>` MP4, `aria-label`, hidden `<button class="play" aria-label="Video abspielen">` with an inline SVG triangle); verify in the markup that `controls` is set and the button carries `hidden`, so without JS the browser's controls play the video (checked in a real browser after deploy)
- [x] 2.2 Add the video block to the existing inline `<script>` (remove `controls`, show the button; on click `play()`, set `controls`, hide the button; set `controls` even if `play()` rejects) and update the script's leading comment; verify in headless Chrome that before the click `readyState` is 0 and no MP4 is requested, and after the click the video plays, `controls` is set and the button is hidden; Return/Space come from the native `<button>`
- [x] 2.3 Add `.frame.video` (16:9 `aspect-ratio`, video fills it) and `.play` (centred, accent colour, hover, `:focus-visible`, smaller in the narrow-screen media query) to `website/style.css`; verify at 1440 px and at 390 px width (responsive mode) that the frame keeps 16:9 before the poster loads, there is no horizontal scrolling and the button is centred

## 3. English home page

- [x] 3.1 Encode `~/Downloads/fernsy-the-mac-odyssey.mp4` with the same Swift encoder and settings as 1.2 and save it as `website/assets/en-fernsy-video.mp4`; verify size 10–15 MB, 1920×1080, H.264/AAC, ≈44 s and `moov` at the start
- [x] 3.2 Extract the closing frame at 41 s as `website/assets/en-fernsy-video-poster.jpg` (JPEG via `sips`, quality 80); verify it shows the English closing text and is under 250 KB
- [x] 3.3 In `website/en/index.html`, replace the hero image with the same `.frame.video` block (English poster and MP4, `aria-label`s "Video: Fernsy – the Mac odyssey" and "Play video") and the same script block; verify in headless Chrome (file URL) that no MP4 is requested before the click and the English video plays after it

## 4. Integration check

- [x] 4.1 Run `openspec validate --all --strict`; verify it passes
- [x] 4.2 Ask the user to confirm; commit with a `Release-Note-de`/`Release-Note-en` pair (e.g. "Die Startseite zeigt ein Video über Fernsy, das per Klick auf Play startet." / "The home page shows a video about Fernsy that starts when you click Play.") only after their agreement

## Workflow follow-up

- Archive the change on the branch (`/opsx:archive`) so the spec update lands with the code.
- Merge into `main` and push only when the user agrees; the Pages workflow then publishes the site.
- On https://www.fernsy.app/ and /en/, in Safari, Chrome and Firefox with the network panel open: `fernsy-video.mp4` is not requested before Play and plays with sound after it; Tab + Return/Space starts it; with JavaScript off the poster shows with native controls and plays. If a browser requests the file early, apply the fallback from design.md (Risks) in a follow-up fix.
- On an iPhone: the video plays inline after a tap, and full screen works from the controls.
