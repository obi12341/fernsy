# Design

## Context

- See proposal.md for why and scope; the behaviour is in `specs/website/spec.md`.
- `website/` is static HTML with one `style.css`, no external resources, and one inline script
  on the home page (gallery tabs, which also removes the `no-js` class from `<html>`).
- The hero is `<div class="frame"><img src="assets/player-live.webp" …></div>` inside
  `section.hero`. `.frame` has rounded corners, a shadow, `overflow: hidden` and a dark
  background, and is at most 1120 px wide.
- Source videos: `~/Downloads/fernsy-die-mac-odyssee.mp4` (German) and
  `~/Downloads/fernsy-the-mac-odyssey.mp4` (English), each 1920×1080, 44 s, H.264 + AAC,
  about 7.3 Mbit/s, 40 MB. Each shows text in its language, so each page gets its own.
- Tools on the Mac: `avconvert` (presets only, no bitrate setting), `swift` with AVFoundation,
  `sips`. No `ffmpeg`, no `cwebp`.
- `.github/workflows/pages.yml` uploads all of `website/` as the Pages artifact.

## Goals / Non-Goals

**Goals:**
- No bytes of the video are loaded until the visitor presses Play.
- The poster is about as light as the hero image it replaces and keeps the layout from
  jumping (fixed 16:9 box).
- The videos are sharp enough for the code and UI text in it at 1080p.

**Non-Goals:**
- Adaptive streaming (HLS/DASH) or several resolutions.
- A custom player UI beyond the start button (after start, the browser's controls are used).

## Decisions

### 1. Native `<video>` with a start button over the poster

Markup in the hero frame:

```html
<div class="frame video">
  <video controls preload="none" playsinline poster="assets/fernsy-video-poster.webp"
         width="1920" height="1080" aria-label="Video: Fernsy – die Mac-Odyssee">
    <source src="assets/fernsy-video.mp4" type="video/mp4">
  </video>
  <button class="play" type="button" aria-label="Video abspielen" hidden>…SVG triangle…</button>
</div>
```

- `preload="none"` and no `autoplay` keep the file unrequested until playback.
- `playsinline` keeps iPhone Safari from going full screen right away.
- Without JS, the `controls` attribute gives every browser a way to play. The button stays
  `hidden`.
- The inline script removes `controls` and shows the button. A click on the button calls
  `video.play()`, sets `controls` again and hides the button for good. The button is a real
  `<button>`, so keyboard and screen readers work without extra code. The gallery code
  stays as it is; the video part is its own small block in the same `<script>`.
- If `play()` is rejected (rare, since it is a user gesture), the script still sets
  `controls`, so the visitor can use the browser's play control.

Rejected:
- **Only native controls, no overlay:** Chrome and Firefox show just a small play icon in
  the control bar at the bottom left. The request is a clear "click Play" moment on the poster.
- **YouTube or Vimeo embed:** third-party requests and cookies on a page whose privacy
  statement says Fernsy collects nothing; the site has no external resources so far.
- **Autoplay muted with a loop:** the user wants playback only on click, and it would load
  40 MB on every visit.

### 2. Re-encode once, locally, as H.264/AAC MP4

The file is encoded once on the Mac and committed, like the rendered mockup images. Neither CI
nor the site encodes anything.

**Steps:**
1. Copy the source into a fresh scratchpad folder.
2. Encode with `avconvert --preset Preset1920x1080` (H.264, AAC, fast start) and check the
   size.
3. If the result is above 15 MB, encode with a short Swift script (AVAssetReader +
   AVAssetWriter, kept in the scratchpad, not in the repo) at a fixed rate:
   - H.264 High profile at about 2.5 Mbit/s, 1920×1080, same frame rate;
   - AAC at 128 kbit/s;
   - `shouldOptimizeForNetworkUse = true`.
   The target is 10–15 MB.
4. Check the result by eye at full screen: text in the code and app scenes must stay
   readable. If not, raise the bitrate step by step, up to about 20 MB.

**Result (25 Oct 2026):** `avconvert --preset Preset1920x1080` only copied the stream, so the
output was still 40 MB: the source already matches the preset. The Swift encoder at a
2.5 Mbit/s target gave 13.8 MB: H.264 1920×1080 at 60 fps (about 2.4 Mbit/s actual), AAC at
about 125 kbit/s, 44.0 s, with `moov` before the media data. The user checked it at full
screen and found the text readable. The Swift scripts stay out of the repo; for a new video,
rebuild them from this description.

**Codec:** H.264 (not HEVC), because every current browser on every OS plays it.

Rejected:
- **Committing the 40 MB original:** about three times the needed size for every visitor
  who presses Play, and every Pages deploy.
- **HEVC only:** smaller, but not reliably playable in Firefox and Chrome outside Apple
  hardware.
- **HEVC + H.264 as two `<source>`s:** both files in the repo for a few MB of savings.
- **GitHub Release asset or Git LFS:** release assets are served with
  `Content-Disposition: attachment` from another host and cannot be relied on for range
  requests in a `<video>`. GitHub Pages does not serve LFS files.

### 3. Poster from a frame of the video

The poster is generated with `AVAssetImageGenerator` (Swift, scratchpad) at 1920×1080. The
frame is a title frame or a typical scene, chosen together with the user. It is saved as WebP
if a WebP encoder is available, otherwise as JPEG via `sips` at quality 80, as in the website
redesign. Target: under 250 KB. The name is `fernsy-video-poster.webp` or `.jpg`.

**Result:** The user chose the closing frame at 41 s (Fernsy icon, name and "Dein IPTV-Zugang
als echte Mac-App"). `sips` reads WebP but cannot write it, and `cwebp` is not installed, so
the poster is `fernsy-video-poster.jpg` (JPEG, quality 80, 100 KB).

### 4. One video per language, `en-` prefix

The German files are `assets/fernsy-video.mp4` and `assets/fernsy-video-poster.jpg`. The
English ones are `assets/en-fernsy-video.mp4` and `assets/en-fernsy-video-poster.jpg`, the
same way the mockup images use the `en-` prefix. Both pages use the same markup and the same
`.frame.video` styles. The script block is duplicated in each page, like the gallery script,
because the site has no shared JS file. Only the `aria-label`s are translated.

The English video arrived while this change was being applied, before anything was
committed, so it joined this change instead of a follow-up change. It was encoded with the
same settings: 13.9 MB, H.264 1920×1080 at 60 fps (about 2.4 Mbit/s), AAC, 44.0 s. Its poster
is the same closing frame at 41 s ("Your IPTV subscription as a real Mac app."), 104 KB.

### 5. Styles

- `.frame.video` uses `aspect-ratio: 16 / 9`, and the `video` fills it with
  `display: block; width: 100%; height: 100%; object-fit: cover`. The box therefore has its
  height before the poster loads.
- `.play` is centred over the frame: a round button about 88 px wide (64 px under the
  existing narrow-screen breakpoint), in the accent colour with a white triangle, a hover
  state like `.button.primary`, and `:focus-visible` like the tab buttons.
- The current hero shadow and the maximum width stay.

## Risks / Trade-offs

- **[Repo and deploy grow by about 10–15 MB]** → One video, encoded once. A replacement
  overwrites the file, so history grows only when the video is changed.
- **[The re-encode blurs text in the video]** → Visual check at full screen (step 2.4), and
  the bitrate is raised if needed.
- **[A browser may request the video despite `preload="none"`]** → Headless Chrome was
  checked locally: no MP4 request before the click. Safari, Firefox and the iPhone are
  checked on www.fernsy.app after the Pages deploy; no local web server is kept for it. If
  one still fetches the file, the script removes the `<source>` at load and adds it back on
  click; the markup keeps it, so the no-JS case still works.
- **[Pitfall: Safari needs HTTP Range requests for `<video>`]** → `python3 -m http.server`
  does not answer them, so Safari will not play the video from it. GitHub Pages does answer
  them. For a local Safari test, use a server with Range support.
- **[The video's sound]** → It plays with sound only after a click, which browsers allow.
- **[No captions]** → Out of scope (proposal). The video has `aria-label`; the headline and
  the text below say the same things.

## Migration Plan

Static files only; the Pages workflow publishes them on merge to main. Rollback: revert the
commit. `assets/player-live.webp` and `assets/en-player-live.webp` are no longer referenced
by the hero but stay in `assets/`, so a rollback or a fallback needs no new render.
