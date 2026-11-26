# Tasks

## 1. Model

- [x] 1.1 `CloudModel.offersSubscription`: true while no subscription is active (no entitlement and the account is not active), also in the grace period
- [x] 1.2 Tests in `CloudModelTests`: none, active, grace and an active web subscription

## 2. Settings on iPhone, iPad and Apple TV

- [x] 2.1 iOS `CloudSettingsView`: offer section when `offersSubscription`, account section when `canUseCloud`, both in the grace period
- [x] 2.2 tvOS `CloudSettingsScreen`: the same
- [x] 2.3 Checked in the simulators (demo server, dev cloud server with `TEST_RUNNER_IPTV_CLOUD`/`IPTV_CLOUDTOKEN`, `IPTV_CLOUDKEY=local`): `CloudRecordingsUITests` `testOfferWithoutAMac` and `testCloudSettingsShowAccount` plus `AssistantUITests` pass on the iPad Air 11-inch (M4) and on Apple TV 4K; the grace state itself is covered by `CloudModelTests` (no dev account in grace)

## 3. App Store

- [x] 3.1 iOS review notes: where the subscription is and how to see the expired state
