# Spec Delta

## ADDED Requirements

### Requirement: Start's Jellyfin rows follow the server when the app comes back
When the app comes back to the front on iPhone, iPad or Apple TV, or is activated on the Mac,
with a Jellyfin account signed in, it SHALL load the server's items to continue and next episodes
again, and Start SHALL show them without the user leaving it. The Mac SHALL ask at most once a
minute, however often the app is activated.

#### Scenario: Continued in another Jellyfin client
- **WHEN** the iPhone app is in the background with Start open, the user watches a Jellyfin film
  to minute 30 in another client, and opens the iPhone app again
- **THEN** "Weiterschauen" and the large entry show the film with that progress, without a tab change

#### Scenario: Episode finished elsewhere
- **WHEN** the user finishes an episode on the Mac while the Apple TV app is left, and opens the Apple TV app again
- **THEN** "Nächste Folge" shows the episode after it

#### Scenario: Server not reachable
- **WHEN** the app comes back to the front and the Jellyfin server does not answer
- **THEN** Start keeps the rows it had
