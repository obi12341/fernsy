## MODIFIED Requirements

### Requirement: Subscription
Fernsy Cloud SHALL require an auto-renewable in-app subscription that can be bought and
restored in every app, the Apple TV included. It SHALL include the recordings cloud and the
assistant (see `assistant`). Apple's purchase confirmation SHALL be the only dialog. Settings
SHALL show its state (none, active with used and total storage and the assistant requests used
this month, ending or ended with dates).

#### Scenario: Restore
- **WHEN** a user who subscribed on the iPad turns the switch on on the Mac and chooses "Restore purchases"
- **THEN** the subscription counts as active and the switch is on, without a sign-in

#### Scenario: Subscribing on the Apple TV
- **WHEN** a user subscribes in the Apple TV's settings
- **THEN** after Apple's purchase confirmation the Apple TV shows the subscription as active and the assistant is available, and the Mac's switch can be turned on without buying again

#### Scenario: Offer without a Mac
- **WHEN** a user who never ran Fernsy on a Mac opens Settings › Fernsy Cloud on the iPhone
- **THEN** the offer shows, naming the assistant on all devices and the recordings cloud with Fernsy on a Mac

## REMOVED Requirements

### Requirement: Offer only with a Mac
**Reason**: The subscription now includes the assistant, which is useful on every device without
a Mac (decided with the user, 2026-11-01).
**Migration**: iPad, iPhone and Apple TV offer the subscription always; the offer explains that
recordings come from Fernsy on a Mac.
