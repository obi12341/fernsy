# Design

How live reconnects stay seamless. Documents existing code (`HTTPByteSource`,
`PlaybackSession.admitLive`, `ContentHistory`, `TSAudioTap`); see proposal.md for why.

## Context

Xtream providers close or stall live connections every few minutes. A new connection
usually starts with a replay of the server's buffer (seconds we already played), and the
load balancer may hand it to another backend that stamps the same channel with an
unrelated clock (offsets of minutes). Packets are byte-identical across backends.

## Decisions

### Replace the connection inside the byte source
- Watchdog every 0.5 s: reconnect when no data for 4 s while the player reports < 4 s ahead,
  or after 30 s regardless; a reconnect without response after 6 s is retried. Some
  channels deliver in segment-sized bursts with seconds of silence, hence the coupling to
  the player's buffer instead of a fixed idle timeout.
- First retry on the same edge host (URL after redirects), later attempts via the load
  balancer URL; delays 0.2 s, then 0.5 s × attempt (single-connection servers need time
  to free the slot). Attempts count per incident and reset after 10 s of stable data;
  8 attempts, then the engine does a full restart.
  - Rejected: always going through the load balancer – usually lands on another backend
    and forces a clock realignment that the same edge avoids.
- New bytes are appended to the same buffer. A TS packet cut mid-way is removed when not yet
  read (keeps 188-byte alignment). The junction offset is recorded; `read` stops exactly at
  it and calls `onRejoin` before handing out the new connection's bytes, so the demuxer
  side knows where each connection begins.
- An offline placeholder redirect during a reconnect ends the in-place attempt; the full
  restart then reports the channel offline.

### Packets know their connection
FFmpeg emits packets well after their bytes were read, so after quick reconnects packets of
older connections are still arriving. Each connection keeps `{start byte, cut, decided}`;
a packet's connection is the last one starting at or before `pkt.pos` (packets split out of
one PES have no position and inherit their stream's last connection). Each is placed with
its own connection's `cut` (seconds subtracted from stream time = output timeline).

### Content fingerprints (ContentHistory)
- Key = hash of (stream salt, packet size, first 2048 bytes). Cheap for multi-MB UHD
  keyframes, unique enough for compressed media.
  - Rejected: hashing whole packets – too slow for UHD keyframes on the demux thread.
- Ring of the last 8192 played packets → their output time; a repeated key points to its
  latest occurrence.
- Keys only for the stream that drives alignment: video, or audio for radio channels.
  - Rejected: audio for alignment – many identical frames (silence) give false matches.

### Admitting packets of a new connection (admitLive)
For a stream's first packets from a connection newer than the one it last rejoined:
1. Undecided connection and the key is in the history → `cut = streamTime − knownTime`
   (exact clock offset of the new backend), connection decided, packet dropped as duplicate.
2. Otherwise `out = streamTime − cut`; `out ≤ last` (within 60 s) → duplicate, dropped.
3. A big jump (> 10 s forward or > 60 s back) on an undecided connection waits up to 150
   packets for a content match before it is believed (another backend's clock).
4. Rejoin: the first stream to rejoin decides the cut for all streams (keeps A/V in sync).
   Gaps of 0.5–10 s are closed on the timeline (`cut += gap − 0.04`); video after a gap
   > 0.5 s waits for the next keyframe so the decoder shows no broken references.
5. Remaining jumps > 10 s in the clock stream resynchronize playback (flush + preroll).
- Rejected: timestamp-only deduplication – fails as soon as the backend clock differs.

### Repaired audio (TSAudioTap) follows the same rules
Tapped frames are fingerprinted with their own salt; after a reconnect, frames found in the
history are skipped, and new frames wait until video has decided the connection's cut
(radio-only taps continue directly). Frames without a PES timestamp after a reconnect
continue from the previous frame's end.

### Interaction with timeshift
The tuner session (`.tuner` mode) runs exactly this logic before packets reach
`TimeshiftWriter`. A full tuner restart is a new session with an empty history, so the
writer drops backward steps as replays only during the first 15 s of a new connection and
otherwise treats every clock jump as a new epoch (see the archived
add-timeshift-and-recordings design).

## Risks / Trade-offs

- [Hash collision on the first 2 KB] → practically irrelevant for compressed video; would
  cause one wrongly dropped packet.
- [History of 8192 video packets ≈ 3 min at 50 fps, 5 min at 25 fps] → replays longer than that are treated as
  new content (repeated scenes) – not seen with real providers.
- Debug switches to reproduce: `IPTV_TESTNET=drop:15,stall:40`, `IPTV_TESTCLOCK=<s>` (each
  reconnect lands on a "backend" whose clock is that much further ahead).
