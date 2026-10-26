# Proposal

## Why

On 2026-10-25, during a live F1 recording, the provider's server kept the connection open but
delivered only about 1 Mbit/s instead of the 6 needed. The connection watchdog only reacts to
complete silence, and each trickle of bytes reset it. Playback froze ten times in
2½ minutes without a reconnect. The first reconnect came when the connection finally went
silent, and it went back to the same slow server, which dropped and rejected Fernsy again
90 s later. The recording lost about 100 s of the race.

## What Changes

- A live connection that delivers clearly slower than real time is replaced, even though
  data still arrives. Slowness is measured on the content's timeline in the timeshift buffer,
  so it works the same with or without someone watching (recording only, watching behind
  live).
- A reconnect caused by slow delivery, or by a stall shortly after slow delivery, skips the
  current edge server and goes through the provider's load balancer at once.
- The log names the server for every live connection, including the first one, and says
  when a reconnect happened because of slow delivery.
- The user is told where the problem lies. While a live stream comes in too slowly or stalls,
  the player shows a card saying that the channel arrives too slowly from the provider and
  that Fernsy is switching servers, instead of a bare spinner. When a switch to another
  provider server brings the stream back, a short note says so. If macOS reports no network
  at all, the card says "Keine Internetverbindung" instead, so the provider is not blamed for
  the user's own outage.
- A recording that misses content keeps a note of each gap of 10 s or more (time and
  length) and names the provider's delivery as the cause in the Recordings section, so a
  hole in the file is not taken for a Fernsy bug.
- A debug switch simulates a trickling connection for tests against the demo server.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: new requirements "Slow live delivery" (slow-delivery detection, which server a
  reconnect tries first, the rule for when switching does not help, delivery figures in the
  log) and "Stall cause in the player" (provider and no-internet cards, the note after a
  server switch); "Seamless live reconnect" logs the server of every connection.
- `recordings`: new requirement "Gaps in recordings".

## Out of Scope

- Filling the gap in a recording with content from another source (the provider has no
  catch-up for most channels).
- Opening a second connection in parallel to test another server (single-stream accounts).
- Detecting slowness for films and series (VOD downloads keep their existing continuation
  logic).
- Changes to the player's own buffering, the attempt limits or the full restart.
- Showing server names or rates in the player UI; the info overlay already counts reconnects
  and shows the last reason.
- Proving whose network is at fault beyond what Fernsy can observe (macOS network state, a
  faster server after the switch). Fernsy states what it saw, not more.
- Gap notes in the MCP tools and for Jellyfin or VOD playback.

## Impact

- `Fernsy/Player/HTTPByteSource.swift`: watchdog rule, edge choice, logging, debug throttle.
- `Fernsy/Player/LiveTuner.swift`, `PlaybackSession.swift` (tuner mode),
  `TimeshiftBuffer.swift`: hand the buffer's newest content time to the connection.
- `PlaybackSession.swift`: `IPTV_TESTNET` gets a `trickle` action (DEBUG only).
- `Fernsy/Views/PlayerScreen.swift`, `PlayerEngine.swift`: provider and no-internet cards,
  the note after a server switch; a network path monitor (Network framework, covered by the
  existing client entitlement).
- `Fernsy/Recording/Recorder.swift`, `Fernsy/Views/RecordingsView.swift`: gap list per
  recording (optional field in the recordings JSON, older files stay readable).
- New strings for the reconnect reason, cards, note and gaps (German and English).
- No new dependencies, entitlements or server changes.
