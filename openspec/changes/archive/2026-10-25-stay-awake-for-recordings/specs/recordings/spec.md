## MODIFIED Requirements

### Requirement: Recordings run while the app runs
Recordings SHALL run while Fernsy is open, also with all windows closed. Per Settings ›
Aufnahmen › "Mac wach halten" (off, 1, 3, 6, 12 or 24 hours, or always; default 6 hours) the
Mac SHALL be kept from idle sleep during a recording and while a scheduled one starts within
that time, and allowed to sleep again otherwise; "off" never keeps it awake. Recordings whose
time passed while the app was not running are marked missed.

#### Scenario: Window closed
- **WHEN** all Fernsy windows are closed before a scheduled recording
- **THEN** the recording still happens

#### Scenario: App not running
- **WHEN** Fernsy was quit during a scheduled show
- **THEN** that recording is listed as missed

#### Scenario: Recording later tonight
- **WHEN** the setting is 6 hours and a recording is scheduled in 4 hours
- **THEN** the Mac does not go to idle sleep until the recording has finished

#### Scenario: Recording far ahead
- **WHEN** the setting is 6 hours and the only scheduled recording starts tomorrow
- **THEN** the Mac may go to idle sleep as usual

#### Scenario: After the last recording
- **WHEN** a recording ends and no other recording starts within the set time
- **THEN** Fernsy stops keeping the Mac awake

#### Scenario: Always
- **WHEN** the setting is "always" and any recording is scheduled
- **THEN** the Mac does not go to idle sleep until no recording is scheduled or running

#### Scenario: Switched off
- **WHEN** the setting is "Aus" and a recording runs
- **THEN** Fernsy does not keep the Mac awake, and the Mac may go to idle sleep as usual
