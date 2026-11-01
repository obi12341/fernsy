# assistant Specification

## Purpose
The assistant inside the Fernsy apps: requests in the user's words, answered briefly and carried
out with Fernsy's own tools on Mac, iPhone/iPad and Apple TV, as part of the Fernsy Cloud
subscription, with consent before data leaves the device.

## Requirements

### Requirement: Assistant in every app
With an active Fernsy Cloud subscription, the Mac, iPhone/iPad and Apple TV apps SHALL offer an
assistant that takes a request in the user's words, answers briefly in the app's language and
acts on Fernsy: play a channel, film, episode or recording, open a page, search the guide and
the library, and schedule or cancel a recording on a device that records.

#### Scenario: Play by request
- **WHEN** the user asks "spiel ZDF"
- **THEN** ZDF plays, and the answer names the channel and what is on

#### Scenario: Schedule by request
- **WHEN** the user asks on the Mac to record tonight's Tatort
- **THEN** the show is scheduled, and the answer names channel, start time and that it is recorded

#### Scenario: Question without action
- **WHEN** the user asks "was läuft heute Abend im Ersten?"
- **THEN** the answer lists tonight's shows on Das Erste and nothing starts playing

### Requirement: Input on each platform
The Mac and iPhone/iPad SHALL take requests typed or dictated in a text field and keep the
conversation of the current session. The Apple TV SHALL take one request at a time in an overlay
whose text field accepts dictation, show the answer and carry out its action, without a chat
history.

#### Scenario: Apple TV
- **WHEN** the user opens the assistant on the Apple TV, dictates "zeig mir neue Filme" and confirms
- **THEN** the overlay shows a short answer and the films page opens

#### Scenario: Follow-up on the iPad
- **WHEN** the user asks "was läuft heute Abend?" and then "nimm den zweiten auf"
- **THEN** the assistant understands the second request from the first one

### Requirement: Fernsy topics only
The assistant SHALL help only with Fernsy: channels, the guide, films, series, Jellyfin, recordings
and playback. It SHALL decline other requests in one sentence, and its answers SHALL stay short.

#### Scenario: Off-topic request
- **WHEN** the user asks the assistant to write an essay
- **THEN** it answers in one sentence that it helps with Fernsy, and the request counts against the allowance

### Requirement: Allowance and its end
The assistant SHALL be limited to a monthly number of requests per subscription and a short-term
rate. Settings › Fernsy Cloud SHALL show the requests used this month. When the allowance is used
up or the subscription is not active, the assistant SHALL say so and when it is available again,
instead of answering.

#### Scenario: Allowance used up
- **WHEN** the user has used all requests of the month and asks again
- **THEN** the assistant says the monthly requests are used up and the date they renew

#### Scenario: Without subscription
- **WHEN** a user without an active subscription opens the assistant
- **THEN** it offers Fernsy Cloud and sends nothing

### Requirement: Consent before the first request
Before the assistant sends its first request on a device, the app SHALL say which data it sends
(the request, the conversation, and the channels, guide, library, favourites and recently watched
items a request needs) and to which provider, and send nothing until the user agrees. The user
SHALL be able to withdraw the consent in Settings.

#### Scenario: First use
- **WHEN** a subscriber opens the assistant for the first time on the iPad
- **THEN** the consent screen shows, and no request leaves the device before "Agree"

#### Scenario: Withdrawn
- **WHEN** the user withdraws the consent in Settings
- **THEN** the assistant shows the consent screen again before its next request
