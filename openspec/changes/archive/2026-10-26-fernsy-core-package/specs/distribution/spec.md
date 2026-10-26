## ADDED Requirements

### Requirement: Automated tests gate builds
The logic Fernsy shares across platforms (provider and Jellyfin data, channel names, the
recording plan, recording gaps, the slow-delivery rule, track choice, the app log) SHALL be
built as a separate module for macOS and tvOS, with automated tests. CI SHALL run these tests
and build the module for tvOS on every push to `main` and to change branches, and SHALL NOT
publish a nightly or a release from a commit whose tests fail. The tests SHALL need no network
and no provider account.

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
