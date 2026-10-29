## MODIFIED Requirements

### Requirement: iPhone and iPad app in CI
CI SHALL build the iPhone and iPad app for the iOS simulator on pushes to `main` that change
more than specs and docs, and on pull requests, in a job of its own named for the iPhone and
iPad app, apart from the Apple TV job; a nightly or release SHALL NOT be built from a commit
where it fails to build.

#### Scenario: The iPhone app stops building
- **WHEN** a commit breaks the iOS target
- **THEN** the push's CI run fails, and no nightly is published from it

#### Scenario: Which app broke
- **WHEN** a commit breaks the iOS target but not the Apple TV app
- **THEN** the run shows the iPhone and iPad job failed and the Apple TV job passed
