## MODIFIED Requirements

### Requirement: Log kept across one restart
The log SHALL be kept in a file in the app's own Caches folder for the current and the
previous app run, each limited in size (oldest entries dropped first). It SHALL never be sent
anywhere by Fernsy; its only reader outside the app is the user's own assistant, through the
local MCP server once the user has switched it on.

#### Scenario: After a restart
- **WHEN** the user quits Fernsy, starts it again and opens the log
- **THEN** the entries of the previous run can be shown

#### Scenario: MCP server off
- **WHEN** the MCP server is switched off
- **THEN** no program outside Fernsy can read the log through Fernsy
