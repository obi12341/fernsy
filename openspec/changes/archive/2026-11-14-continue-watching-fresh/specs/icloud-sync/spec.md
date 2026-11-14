# Spec Delta

## ADDED Requirements

### Requirement: Changes from other devices when the app comes back
When the app comes back to the front on iPhone, iPad or Apple TV, or is activated on the Mac,
with "Mit iCloud abgleichen" on, it SHALL take the synced values iCloud holds from the user's
other devices at that moment, without waiting for a notification, and SHALL show them without
the user leaving the screen that is open.

#### Scenario: Film continued on the Mac
- **WHEN** the iPhone app is in the background with Start open, the user watches a provider film
  on the Mac to minute 50, and opens the iPhone app again once iCloud has the position
- **THEN** "Weiterschauen" and the large entry show that film with its new progress, without a tab change

#### Scenario: Favourite added elsewhere
- **WHEN** the Apple TV app was left for the Home Screen, a channel becomes a favourite on the
  iPhone, and the user opens the Apple TV app again
- **THEN** the channel is among the favourites

#### Scenario: Sync switched off
- **WHEN** "Mit iCloud abgleichen" is off and the app comes back to the front
- **THEN** nothing is taken from iCloud

### Requirement: The series of a started episode is synced
With a resume position of a provider episode the apps SHALL keep which series the episode belongs
to, and SHALL sync it with "Mit iCloud abgleichen" on, in a way that devices running an older
version neither lose their positions nor remove it. A position without a series (saved by an
older version) SHALL get one as soon as a device with this version has that series' episode list
or plays the episode.

#### Scenario: Episode started on the Mac
- **WHEN** the user stops episode 3 of a provider series on the Mac after 10 minutes
- **THEN** the user's iPhone knows the position and the series it belongs to

#### Scenario: A device with an older version syncs in between
- **WHEN** a device with an older version sends its own positions after the Mac sent the episode's
- **THEN** the iPhone still knows the episode's series, and the older device still resumes its
  films and episodes where they were

#### Scenario: Position from an older version
- **WHEN** an episode's position was saved by an older version, and the user opens that series'
  page on an updated Mac
- **THEN** the series is added to the position and reaches the other devices

### Requirement: Finished on one device, finished on all
A provider film or episode watched to its end on one device SHALL count as watched on the user's
other devices, with "Mit iCloud abgleichen" on, and SHALL leave their "Weiterschauen" and large
entry, also when those devices still hold an older position for it. Starting it again afterwards
on any device SHALL keep the new position.

#### Scenario: Film finished on the Mac
- **WHEN** the user stopped a provider film at 20 minutes on the iPhone and later watches it to its end on the Mac
- **THEN** the iPhone no longer lists it in "Weiterschauen" and marks it as watched

#### Scenario: Watched again
- **WHEN** the film finished on the Mac is started again on the iPhone and stopped at 5 minutes
- **THEN** "Weiterschauen" lists it at 5 minutes on the iPhone and on the Mac
