## MODIFIED Requirements

### Requirement: Automated tests gate builds
The logic Fernsy shares across platforms (provider and Jellyfin data, channel names, the
recording plan and gaps, the slow-delivery rule, track choice, the app log) SHALL be a
separate module for macOS and tvOS with tests, which CI SHALL run with a tvOS build on pushes
to `main` changing more than specs and docs, and on pull requests. A nightly or release
SHALL reuse a passing run of its commit or run them, never publishing a failing one. The
tests SHALL need no network and no provider account.

#### Scenario: A change breaks channel-name parsing
- **WHEN** a commit changes how "|DE| RTL FHD" is split into name, country and quality
- **THEN** the test run for that push fails and names the case

#### Scenario: Nightly after a failing commit
- **WHEN** the newest commit on main has failing tests at nightly time
- **THEN** no nightly is published, and the previous nightly stays in place

#### Scenario: Shared logic stops building for tvOS
- **WHEN** a commit makes the shared module use something only macOS has
- **THEN** the push's CI run fails on the tvOS build

#### Scenario: Tests offline
- **WHEN** the tests run on a machine without network access
- **THEN** they pass, because network answers come from recorded examples

#### Scenario: Nightly after a tested merge
- **WHEN** the tests passed for the merge commit on `main` and the nightly is started for it
- **THEN** the nightly builds without running the tests again

#### Scenario: Push to a change branch
- **WHEN** a commit is pushed to a change branch
- **THEN** no test run starts for it

#### Scenario: Spec-only commit on main
- **WHEN** a push to `main` changes only files under `openspec/` and Markdown files
- **THEN** no test run starts, and a nightly from that commit runs the tests itself

### Requirement: Apple TV app in CI
CI SHALL build the Apple TV app for the tvOS simulator and run its UI test with the demo
account on pushes to `main` that change more than specs and docs, and on pull requests; a
nightly or release SHALL reuse that run for its commit or run it itself, and SHALL NOT be built
when it fails.

#### Scenario: The Apple TV app stops building
- **WHEN** a commit breaks the Apple TV target
- **THEN** the push's CI run fails, and no nightly is published from it
