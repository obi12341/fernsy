## MODIFIED Requirements

### Requirement: Apple TV app in CI
CI SHALL build the Apple TV app for the tvOS simulator and run its UI test with the demo
account on pushes to `main` that change more than specs and docs, and on pull requests; the UI
tests SHALL run split into parts in parallel, every test in exactly one part, and the run SHALL
fail when any part fails; a nightly or release SHALL reuse that run for its commit or run it
itself, and SHALL NOT be built when it fails.

#### Scenario: The Apple TV app stops building
- **WHEN** a commit breaks the Apple TV target
- **THEN** the push's CI run fails, and no nightly is published from it

#### Scenario: One part fails
- **WHEN** a UI test in one part fails and the other parts pass
- **THEN** the run fails, the other parts still finish, and the failing part's results are kept

#### Scenario: A new UI test class
- **WHEN** a commit adds a UI test class to the Apple TV tests
- **THEN** it runs in one of the parts without editing the workflow
