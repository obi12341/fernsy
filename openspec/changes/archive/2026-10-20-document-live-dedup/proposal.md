# Proposal

## Why

The baseline mentions only in one sentence how live reconnects avoid repeated scenes and
clock jumps. That logic (content fingerprints of packets, deduplication, lining up backends
with different clocks) is the most provider-specific part of the player and was tuned over
many sessions; without a record, later changes (like the timeshift tuner, which reuses it)
risk breaking it.

## What Changes

- Spell out the observable reconnect behaviors as scenarios of the existing requirement.
- Document the mechanism and its tuning constants with rationale in design.md.
- No code changes.

Out of scope: changing the algorithm.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `playback`: "Seamless live reconnect" gets scenarios for replays, other backend clocks, real gaps and quick repeated reconnects.

## Impact

Documentation only.
