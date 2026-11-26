## MODIFIED Requirements

### Requirement: Subscription end
When the subscription ends, uploads SHALL stop and stored recordings SHALL stay playable and
deletable for 30 days. The apps SHALL show the date after which they are deleted. Renewing
before that date SHALL keep them. While no subscription is active, the grace period included,
Settings › Fernsy Cloud SHALL offer subscribing and restoring purchases on every device.

#### Scenario: Subscription lapsed
- **WHEN** a subscription ended 10 days ago
- **THEN** the cloud recordings play, uploads are not offered, and a note says they are deleted in 20 days unless renewed

#### Scenario: Subscribing again after the end
- **WHEN** a subscription ended 10 days ago and the user opens Settings › Fernsy Cloud on the iPad or the Apple TV
- **THEN** the offer with "Subscribe" and "Restore Purchases" shows above the ended state and the deletion note, and subscribing makes the subscription active again with the recordings kept
