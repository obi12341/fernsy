## MODIFIED Requirements

### Requirement: Subscription
Fernsy Cloud SHALL require an auto-renewable subscription with the recordings cloud and the
assistant (see `assistant`). The App Store apps, the Apple TV included, SHALL sell and restore it
in-app with Apple's confirmation as the only dialog and SHALL NOT mention another way to pay; the
DMG SHALL sell it on fernsy.app with Stripe's payment form. Either SHALL count on every device with
the same cloud key. Settings SHALL show its state (none, active, ending, ended) with dates and usage.
Every place that offers the subscription SHALL show its name, length and price, that it renews
automatically until canceled, and links to the Terms of Use and the privacy policy: Apple's
standard EULA in the App Store apps, the terms on fernsy.app in the DMG, and the privacy page in
the app's language. The Apple TV SHALL show both addresses as text.

#### Scenario: Restore
- **WHEN** a user who subscribed on the iPad turns the switch on on the Mac and chooses "Restore purchases"
- **THEN** the subscription counts as active and the switch is on, without a sign-in

#### Scenario: Subscribing on the Apple TV
- **WHEN** a user subscribes in the Apple TV's settings
- **THEN** after Apple's purchase confirmation the Apple TV shows the subscription as active and the assistant is available, and the Mac's switch can be turned on without buying again

#### Scenario: Offer without a Mac
- **WHEN** a user who never ran Fernsy on a Mac opens Settings › Fernsy Cloud on the iPhone
- **THEN** the offer shows, naming the assistant on all devices and the recordings cloud with Fernsy on a Mac

#### Scenario: Subscribing in the DMG
- **WHEN** a user of the DMG chooses "Subscribe" in Settings › Recordings › Fernsy Cloud and pays on fernsy.app
- **THEN** the Mac shows the subscription as active within a minute of returning to the app, and the iPhone with the same Apple ID can play the cloud recordings without buying again

#### Scenario: Already subscribed
- **WHEN** the account already has an active subscription from Apple or from the website
- **THEN** no app and no checkout page offers buying another one

#### Scenario: Terms at the offer
- **WHEN** a user without a subscription opens Settings › Fernsy Cloud on the iPhone
- **THEN** the offer shows "Fernsy Cloud · 1 month" with the price, that it renews monthly until canceled in the Apple account settings, and the links "Terms of Use (EULA)" and "Privacy Policy", which open Apple's standard EULA and fernsy.app's privacy page

#### Scenario: Terms on the Apple TV
- **WHEN** the assistant on the Apple TV offers the subscription
- **THEN** it shows the price, the renewal note and the addresses of the Terms of Use and the privacy policy as text
