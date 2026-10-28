## MODIFIED Requirements

### Requirement: Synced choices
With "Mit iCloud abgleichen" on, the apps SHALL sync through the user's iCloud, per provider
account: hidden categories and channels, favourites, recently watched channels, pinned
categories and resume positions of provider films and episodes; and for the app: preferred
audio and subtitle languages, recording padding and the switches for the provider's films and
series. A change SHALL reach the user's other signed-in devices without a restart while their
app runs.

#### Scenario: Hiding on the Mac
- **WHEN** the user hides the category "Sport UK" on the Mac
- **THEN** the Apple TV app of the same Apple ID no longer shows it in Live TV, the guide and zapping

#### Scenario: Continuing a film
- **WHEN** the user stops a provider film at 42 minutes on the Apple TV and opens it on the Mac
- **THEN** the Mac offers to resume at 42 minutes

#### Scenario: Switching series off on the Mac
- **WHEN** the user switches "Serien" off in the Mac's settings
- **THEN** the Apple TV app drops its Serien tab and stops downloading the provider's series

#### Scenario: Not synced
- **WHEN** a recording is scheduled on the Mac
- **THEN** it does not appear on the Apple TV
