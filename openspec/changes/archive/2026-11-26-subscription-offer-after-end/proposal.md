# Proposal

## Why

App Review (iOS 2.4.1, Nov 24, 2026) wants to walk the whole purchase flow with an expired
subscription. After a subscription ends, Settings › Fernsy Cloud on iPhone, iPad and Apple TV
shows "Ended …", the deletion note and "Manage Subscription", but no "Subscribe": the offer only
shows while `canUseCloud` is false, and that stays true for the 30-day grace period because the
recordings stay playable. Renewing is only possible through the assistant's offer or Apple's
subscription sheet. The Mac already offers buying again (its upload switch opens the offer when
uploads are not possible).

## What Changes

- Settings › Fernsy Cloud on iPhone, iPad and Apple TV shows the offer ("Subscribe", "Restore
  Purchases", price line and terms) whenever no subscription is active: with none, and after it
  ended, during the grace period as well. In the grace period the state, storage, deletion note
  and the other account rows stay below the offer.
- `CloudModel` gets one place for that decision (`offersSubscription`).

Out of scope:
- The Mac: its upload switch already opens the offer when uploads are not possible.
- The assistant's offer (it already shows without an active subscription).
- The server and the grace period itself.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `recording-cloud`: "Subscription end" also offers subscribing again in the grace period.

## Impact

- `Packages/FernsyCore/Sources/FernsyCore/CloudModel.swift` (`offersSubscription`) and its tests.
- `FernsyiOS/CloudViews.swift` (`CloudSettingsView`), `FernsyTV/Screens/SettingsScreen.swift`
  (`CloudSettingsScreen`).
- App Store review notes for iOS (how to see the expired state).
