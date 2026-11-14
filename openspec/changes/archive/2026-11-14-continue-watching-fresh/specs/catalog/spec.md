# Spec Delta

## ADDED Requirements

### Requirement: Started episodes in Weiterschauen without opening their series
On the Mac, iPhone, iPad and Apple TV, "Weiterschauen" and the large entry of Start SHALL list a
started provider episode whose series is known, whether or not the series' page was opened on
this device or since the app started. The app SHALL load the missing episode lists itself, for the
series of the 20 most recently played started episodes at most, without opening a stream.

#### Scenario: After a relaunch
- **WHEN** the user stopped an episode yesterday on the iPhone and opens the app today after iOS ended it
- **THEN** "Weiterschauen" lists the episode with its series, episode number and time left, and
  tapping it resumes there

#### Scenario: Series started on another device
- **WHEN** the user started a provider series on the Mac that was never opened on the Apple TV
- **THEN** the Apple TV's "Weiterschauen" lists the episode, and the large entry shows it when it
  is the newest item to continue

#### Scenario: Series no longer in the catalog
- **WHEN** the series of a started episode is gone from the provider's catalog, or series are
  switched off for the account
- **THEN** the episode is not listed, and nothing is requested for it

### Requirement: Episode lists kept on the device
The apps SHALL keep the episode lists they load on the device, per provider account, and SHALL
use them to list started episodes at launch before the provider answered, also without a
connection. A series' page SHALL still show the episode list as the provider has it now, and the
kept list SHALL follow it.

#### Scenario: Opened without a connection
- **WHEN** the iPad is offline, and an episode was listed in "Weiterschauen" at the last launch
- **THEN** "Weiterschauen" lists it again

#### Scenario: New episode at the provider
- **WHEN** the provider added an episode to a series whose list is kept, and the user opens the series' page
- **THEN** the page shows the new episode
