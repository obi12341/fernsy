# Proposal

## Why

Switching to a live channel shows a short reset a few seconds after the picture starts: the
picture jumps and the buffer drops by about 10 s. The provider sends its stored last 15–20 s
of the channel as a burst when the connection opens, spread over a few seconds. Fernsy starts
playing 0.5 s in, in the middle of that burst, 5 s behind what has arrived so far; when the rest
of the burst lands, playback is ~17 s behind the newest data, and the rule "jump to the live
edge when more than ~17 s behind for 4 s" makes it jump. The jump is specified behaviour, but it
looks like a glitch on every channel switch.

## What Changes

- A provider's initial backlog no longer makes playback jump: playback keeps running from where
  it started, behind the newest data by however much the burst delivered.
- The player still shows "LIVE" in that state (it follows live; the user did not pause or
  rewind).
- Fernsy never jumps on its own any more. When playback falls more than ~12 s further behind
  than the distance it settled at after starting (e.g. after stalls), it leaves the live state:
  the badge shows the time behind instead of "LIVE", and playback continues where it is.
- Going back to live is the user's action (clicking the badge), which goes to the real edge, as
  today.
- Debug switch to produce lag on demand (`IPTV_TESTSTALL`).

Out of scope:
- Speeding playback up to close the distance (rejected, see design).
- Waiting for the burst before starting (rejected, see design).
- Changing the 5 s start lead or how much timeshift is stored.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timeshift`: "Following live stays close to live" never jumps on its own: the initial backlog
  is played as live, and further lag ends the live state instead of jumping.

## Impact

- `Fernsy/Player/PlayerEngine.swift` (lag baseline, leaving live instead of jumping, debug stall), `README.md`; design decision of `add-timeshift-and-recordings` ("Live edge")
  is refined.
