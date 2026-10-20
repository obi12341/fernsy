# Proposal

## Why

The user wants to add Jellyfin accounts next to Xtream. Before planning that, we need to
know whether Fernsy's player (LGPL-only FFmpeg, VideoToolbox, AVSampleBuffer rendering) can
play typical Jellyfin libraries directly (MKV remuxes with HEVC/HDR/Dolby Vision, TrueHD,
DTS-HD, PGS; web encodes with AV1/Opus/ASS; DVD-era MPEG-2/VC-1/VobSub; music), or whether
Jellyfin has to transcode for us – and what each gap would cost to close.

## What Changes

- An analysis, no app changes: a written report `docs/analysis/jellyfin-playback.md` with
  - a format matrix (container, video, audio, subtitle, HDR/DV, music) → plays directly /
    plays with gaps / needs transcoding or remuxing, each backed by a test result;
  - what Jellyfin offers (Direct Play, Direct Stream/remux, transcoding, subtitle burn-in or
    extraction, device profiles, range requests, authentication) and what that means for us;
  - per gap: options (extend the player, add an LGPL/BSD library, let Jellyfin transcode),
    effort, licensing and App Store implications;
  - a recommendation for the Jellyfin client approach.
- Temporary test tooling in the scratchpad only (probe/decode tools, test files).

Out of scope: building the Jellyfin account, catalog or playback; changing the FFmpeg build
or the player; storing Jellyfin credentials in the repository.

## Capabilities

### New Capabilities

None – analysis only (`skip_specs: true`). A follow-up change will specify Jellyfin support
based on the report.

### Modified Capabilities

None.

## Impact

- New document `docs/analysis/jellyfin-playback.md`.
- Uses the user's Jellyfin server (access provided at implementation time; credentials stay
  out of git) and free test media.
