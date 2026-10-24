# Proposal

## Why

A scheduled recording whose channel delivers nothing when it starts is never recorded. The
recorder waits about 50 seconds for the first data and then marks the recording failed
("Keine Daten vom Sender") for good. A channel the provider reports as offline (redirect to
the offline placeholder) fails it at once. Short outages at the start of a show are common
with IPTV providers, so the user loses recordings they planned in advance.

## What Changes

- A recording that gets no data when it starts keeps trying until its recording window
  (including padding) ends. It starts writing as soon as the channel delivers. The file then
  begins at the first data instead of the planned start.
- A channel the provider reports as offline no longer ends a recording's attempts. The
  connection is retried at a calm interval for as long as a recording needs the channel.
  When only the player uses the channel, it gives up as it does today.
- The same applies while a recording runs: if the channel goes offline mid-show, the
  recording keeps its file and continues writing when the channel comes back. It does not
  end as failed.
- While a recording waits for data, the Recordings list shows it as running with a note
  "Wartet auf den Sender …" instead of showing it as scheduled or failed.
- A recording that got no data at all by the end of its window is marked failed with
  "Keine Daten vom Sender", as it is today.
- New debug switch to simulate a channel without data at the start, for verification
  against the demo server.

Out of scope:
- Retrying recordings that were missed because Fernsy was not running.
- Retrying after the user chose "Skip Recording" in the connection prompt.
- Changing the connection prompt or the single-stream rules. A waiting recording holds its
  connection slot like a running one.
- Retries for the player alone (live TV without a recording), and for films or Jellyfin.
- Notifications about a recording that failed or recovered.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `recordings`: new requirement that a recording keeps trying to get data until its window
  ends, both at the start and after an outage, and how the list shows a waiting recording.

## Impact

- `Fernsy/Recording/Recorder.swift`: `begin` waits until the window ends instead of a
  fixed timeout. `tick` no longer ends a running recording when its tuner reports the
  channel offline. A non-persisted "waiting" state is published for the list.
- `Fernsy/Player/LiveTuner.swift`: with `keepTrying` (a recording owns the tuner), an
  offline failure is retried with a longer delay instead of being final. The timeshift
  buffer and its timeline stay the same across retries, so the running copier continues in
  the same file.
- `Fernsy/Views/RecordingsView.swift`: shows the waiting note.
- `Fernsy/Player/PlaybackSession.swift` (DEBUG only): a test switch that makes tuner
  connections fail or stay silent for the first seconds.
- `Fernsy/Localizable.xcstrings`: the new German text with its English translation.
- README: the new debug switch.
