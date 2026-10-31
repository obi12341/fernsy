## ADDED Requirements

### Requirement: Display mode follows the content
While the full-screen player shows video and the item's account has matching on, the Apple TV
app SHALL ask tvOS for the frame rate and dynamic range of the picture it shows (deinterlaced TV at its doubled rate, Dolby Vision mapped
to HDR10 as HDR10), so a TV with "Match Content" switches to them. Leaving the player SHALL hand
the mode back to the system. The Live TV preview pane SHALL NOT ask for a mode.

#### Scenario: A film switches the TV
- **WHEN** "Match Content" is on in the Apple TV's settings and the user plays a 23.976 fps film
- **THEN** the TV switches to 23.976 Hz (24p) and back to the interface's mode when the player closes

#### Scenario: Interlaced TV asks for its field rate
- **WHEN** the user plays a 1080i channel with 25 frames per second
- **THEN** the app asks for 50 Hz, the rate of the deinterlaced picture

#### Scenario: HDR10 asks for HDR
- **WHEN** the interface runs in SDR and the user plays an HDR10 episode
- **THEN** the app asks for HDR10 at the episode's frame rate

#### Scenario: Preview pane keeps the mode
- **WHEN** the Live TV preview pane plays the focused channel
- **THEN** the TV keeps the interface's mode

### Requirement: Zapping keeps an unchanged mode
When the player moves to another live channel, episode or item, the Apple TV app SHALL ask for a
new mode only if the frame rate or dynamic range differs from the current request.

#### Scenario: Same kind of channel
- **WHEN** the user zaps from one 50 Hz SDR channel to another
- **THEN** the TV does not switch and shows no black picture

#### Scenario: Different frame rate
- **WHEN** the user zaps from a 50 Hz channel to a 60 Hz channel
- **THEN** the app asks for 60 Hz

### Requirement: Playback waits for the mode switch
When the player starts an item and tvOS switches the display mode for it, the Apple TV app SHALL
hold the start until the switch has ended, or for at most five seconds. A switch while video
already plays (the preview going full screen) SHALL NOT pause it.

#### Scenario: Film start is not lost
- **WHEN** a film starts and the TV takes two seconds to switch
- **THEN** the film starts at its resume position after the switch, not two seconds later

#### Scenario: Preview goes full screen
- **WHEN** the user opens the channel playing in the preview pane full screen and the TV switches to 50 Hz
- **THEN** the channel keeps playing on its connection during the switch

### Requirement: Setting for matching the display mode per account
Settings › IPTV Account and Settings › Jellyfin Server SHALL each offer "Match Frame Rate and
Dynamic Range", with a note that tvOS switches only when "Match Content" is on in the Apple TV's
settings. The IPTV account's option SHALL be off by default and cover everything it plays (live
TV, catch-up, films, series, recordings, cloud recordings); Jellyfin's SHALL be on by default.
While an item's account has it off, the app SHALL NOT ask for a mode for that item.

#### Scenario: Defaults
- **WHEN** a new user signs in to an IPTV account and a Jellyfin server
- **THEN** the IPTV account's option is off and the Jellyfin server's is on

#### Scenario: Zapping with the IPTV option off
- **WHEN** the IPTV account's option is off and the user plays a 50 Hz channel or an IPTV film
- **THEN** the TV keeps the interface's mode

#### Scenario: Jellyfin film with the IPTV option off
- **WHEN** the IPTV account's option is off, Jellyfin's is on, and the user plays a 24 fps Jellyfin film
- **THEN** the app asks for 23.976 Hz or 24 Hz

#### Scenario: Turned off while playing
- **WHEN** the user turns the playing item's account option off
- **THEN** the mode is handed back to the system
