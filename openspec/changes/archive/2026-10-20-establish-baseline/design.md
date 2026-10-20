# Design

Record of the decisions behind Fernsy 1.0 (October 2026), written down after the fact so
later changes do not reopen them by accident. See proposal.md for why this exists.

## Context

Fernsy targets people who already pay for an IPTV subscription with the Xtream Codes API.
Providers are inconsistent: plain HTTP, redirects to changing edge hosts, streams that drop
or stall every few minutes, backends with different clocks, broken audio PIDs, and usually
only one simultaneous stream per account. The app is sold in the Mac App Store.

## Goals / Non-Goals

**Goals:** play what typical providers deliver without visible restarts; a native Mac UI;
App Store compliant; no data collection.

**Non-Goals:** providing or recommending content; M3U playlists or other APIs (Xtream only
so far); Intel Macs; provider catch-up/archive (`tv_archive`) – not built yet.

## Decisions

### Own playback pipeline on FFmpeg + AVSampleBuffer renderers
FFmpeg demuxes and decodes (VideoToolbox hwaccel), video and audio go to
AVSampleBufferDisplayLayer / AudioRenderer under one AVSampleBufferRenderSynchronizer.
- Rejected: AVPlayer – no MPEG-TS over plain HTTP progressive live, no MPEG-2/AC-3 from
  many restreams, no control over reconnects.
- Rejected: VLCKit/mpv – GPL or LGPL-with-GPL-parts, large, harder to sandbox and to tune.

### Network via URLSession, not FFmpeg's HTTP
`HTTPByteSource` feeds FFmpeg through custom I/O. Provider servers accept the system network
stack (curl-like clients get dropped), and URLSession gives redirects, proxies and keep-alive.
FFmpeg is built without network and protocol support.

### Live reconnects inside the session
A dropped or stalled connection (watchdog: no data for 4 s while the player has < 4 s left,
or 30 s regardless) is replaced in place, first on the same edge host, then via the load
balancer. Bytes are appended to the same buffer; packets the new connection replays are
dropped by content hash and timestamp; another backend's clock offset is measured by
content match. Only when that fails does the engine restart the session (max 8 attempts).
- Rejected: restarting the player on every drop – visible black frames and repeated scenes.

### Single-connection accounts drive the design
The old stream is fully closed before a new one opens (zapping waits 400 ms after the last
key press; `open()` retries while the server still holds the old slot). One player window
only. Never test streams on the developer's account while the user watches (see
config.yaml).

### LGPL-only FFmpeg built from source
Homebrew's FFmpeg is GPL (x264/x265), which App Store distribution cannot use. We build
FFmpeg 9.0.2 ourselves: LGPL, decoders only (plus later the MPEG-TS muxer), shared
libraries with @rpath, Metal enabled for `yadif_videotoolbox`. Credits name the source
archive (LGPL source offer).

### Audio rescue (TSAudioTap)
Some restreams write one PES header and append AAC forever under a PMT entry claiming
AC-3; FFmpeg emits that audio ~12 s late. A tap splits ADTS frames out of the raw TS bytes
and timestamps them itself; affected PIDs are remembered per stream URL.

### Program guide
`get_simple_data_table` for the full schedule, `get_short_epg` first for a quick row.
At most 2 concurrent table downloads served last-in-first-out, ref-counted waiters with
cancellation, 200 ms visibility delay per row; disk cache per account (rules in the spec).
Sticky channel column and title offsets are applied at render time (`visualEffect`) so
scrolling does not invalidate the view tree; one observable object per channel row.
- Rejected: preloading all channels – providers rate-limit and answered in 17 s under load.

### App Store setup
Bundle id de.mobilistics.fernsy, Apple Silicon only (user decision), App Sandbox with
network client; ATS exception `NSAllowsArbitraryLoads` because most providers only offer
HTTP and redirect to changing hosts; `ITSAppUsesNonExemptEncryption = NO`; privacy manifest
(UserDefaults CA92.1, file timestamps C617.1). Build numbers are bumped by our scripts
(`manageAppVersionAndBuildNumber = false`) after Xcode once uploaded a run silently.
Store name "Fernsy – IPTV Player"; age rating 18+ because adult categories are only hidden.

### Signing for local builds
Ad-hoc signing ties keychain access to the code hash, so every build asked for the keychain
password. Local DMGs are signed with the Apple Development certificate, whose designated
requirement stays stable. `FERNSY_NO_KEYCHAIN` skips the keychain for smoke tests and demo
recordings; debug builds take `IPTV_SERVER/USER/PASS` from the environment.

### Demo server for App Review
Apple asked for a working account. Instead of handing over a real provider login, a
Cloudflare Worker (`demo-server/`) serves a fictional Xtream catalog; media are assets of
the GitHub release `demo-media`. Live channels are paced in 3 s ranged subrequests (free plan
allows 50 subrequests per request, so connections end after ~75 s and the app reconnects).

### Localization
German is the source language (the developer's language), English is translated in
`Localizable.xcstrings`; strings are synced from the compiler's `.stringsdata` with
`xcrun xcstringstool sync`.

### Repository and license
Public on GitHub (obi12341/fernsy) under GPLv3: anyone may study and modify it, closed
commercial forks are not possible, and mobilistics can still sell the App Store build
(contributions need a CLA for that). Screenshots, builds and other assets stay out of git.

### Website
Static pages in `website/` deployed by GitHub Actions to GitHub Pages on www.fernsy.app;
the bare domain redirects at the DNS provider.

## Risks / Trade-offs

- [Provider quirks not seen yet] → the info overlay and debug switches (`IPTV_TESTNET`,
  `IPTV_TESTCLOCK`) make new cases diagnosable.
- [ATS exception draws review questions] → explained in the review notes.
- [GPLv3 deters some contributors] → accepted; CLA note in README.
