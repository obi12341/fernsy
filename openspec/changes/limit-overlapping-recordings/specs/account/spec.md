## ADDED Requirements

### Requirement: The stream limit is remembered
The number of simultaneous connections the provider reports SHALL be saved per account and
used from app start until a fresh value arrives; only an account that never reported one
counts as one stream. The app SHALL ask the provider again with every catalog refresh, so a
changed package takes effect without signing in again.

#### Scenario: Start without the provider
- **WHEN** an account that reported 3 connections starts Fernsy while the provider cannot be reached
- **THEN** recordings are planned and padded for 3 streams

#### Scenario: Package changed
- **WHEN** the provider reports 2 connections instead of 3 at the next catalog refresh
- **THEN** Fernsy uses 2 streams from then on and recalculates the recordings' padding

#### Scenario: Never reported
- **WHEN** an account has never reported a number of connections
- **THEN** Fernsy counts it as one stream
