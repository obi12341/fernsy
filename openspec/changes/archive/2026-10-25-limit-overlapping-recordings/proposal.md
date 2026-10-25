# Proposal

## Why

Back-to-back recordings on different channels break on accounts with few streams. On a
single-stream account, show A on channel 1 (until 21:45) and show B on channel 2 (from 21:45)
both plan the default 10 minutes of padding. At 21:35, B's pre-roll needs the only
connection. The conflict prompt answers "end A and record B" after a minute, so A loses the
last ten minutes of its real show.

Planning also allows recordings whose shows genuinely overlap. That only surfaces as a
warning, and later as a prompt that drops one of them. Planning should catch both cases up
front, measured against the account's stream limit.

## What Changes

- **Real overlap is refused when planning.** A show's own time is its time without padding.
  If recording a show would need more streams at once than the account allows, Fernsy
  refuses to plan it and names the recordings in the way. This applies to:
  - the guide, the detail pane and the context menu;
  - the player's record button and R key.
- **Padding gives way instead of taking a stream.** When only padding exceeds the limit,
  the padding is shortened so the recordings fit, and planning shows a notice that says by
  how much. The after-padding of the earlier show wins over the before-padding of the later
  one. Padding never reaches into another planned show's own time.
- **Shortening follows the plan.** The shortened padding is recalculated whenever
  recordings are planned or removed, or when padding settings or the stream limit change.
  Removing the neighbour restores the full padding. The Recordings list shows the shortened
  window.
- **Same channel stays as it is.** Recordings on the same channel share one connection, so
  their padding may overlap. Both files keep their full padding.
- **Handover without a prompt.** At the moment one recording's shortened window ends and
  the next begins, the next one does not tune early into the connection still held by the
  first. It takes over when the first releases it, without asking.
- **The stream limit is remembered.** The provider's `max_connections` is saved per account
  and used from app start, also when the provider cannot be reached. Before, it was only held
  in memory and fell back to 1 until the first answer. It is asked for again with every
  catalog refresh, not only once per start.
- **The prompt stays as a fallback.** The prompt at start remains for conflicts with the
  player, and for plans made before this change or before the stream limit dropped.

Out of scope:
- connections used by other devices on the same account;
- changes to the padding settings themselves;
- recordings on the user's real provider during tests (the demo server and `IPTV_MAXCONN`
  are used).

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `account`: new requirement "The stream limit is remembered".
- `recordings`: new requirements "Real overlaps are refused within the stream limit",
  "Padding gives way to other recordings" and "Handover between back-to-back recordings";
  "Recordings list shows the recording window" also shows a shortened window.

## Impact

- `Fernsy/Recording/Recorder.swift`:
  - stream count over time;
  - refusal and shortening when planning;
  - the effective window used by `tick`/`begin`;
  - handover without early tuning;
  - recalculation on change.
- Callers of `schedule`/`recordNow` show the refusal or the notice: `GuideView`,
  `ChannelDetailPane`, `PlayerScreen` and `RecordingsView`.
- `AppModel`: the stream limit is saved in the account folder (`connections.json`), loaded on
  sign-in and at start, and refreshed with the catalog. `updateConnectionLimit` triggers a
  recalculation.
- `Localizable.xcstrings`, README (debug switch for tests).
