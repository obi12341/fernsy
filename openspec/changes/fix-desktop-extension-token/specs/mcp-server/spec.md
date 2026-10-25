## MODIFIED Requirements

### Requirement: Claude Desktop extension
"Zu Claude Desktop hinzufügen …" SHALL build a desktop extension (`.mcpb`) for the current
endpoint and token and open it in Claude Desktop, or let the user save it when Claude Desktop is
missing. The extension SHALL need no Node.js installation and no further input after installing,
carry a valid semantic version, forward MCP messages to the local endpoint, and answer tool calls
with an explanation while Fernsy or its server is not running.

#### Scenario: Adding Fernsy to Claude Desktop
- **WHEN** the user chooses "Zu Claude Desktop hinzufügen …" with Claude Desktop installed
- **THEN** Claude Desktop shows its install dialog for "Fernsy", and right after installing, without filling in anything, Claude can use Fernsy's tools

#### Scenario: Fernsy closed
- **WHEN** Claude calls a Fernsy tool while Fernsy is not running
- **THEN** the call returns that Fernsy must be open with the MCP server switched on

#### Scenario: New token
- **WHEN** the user creates a new token in Fernsy
- **THEN** the installed extension is refused until Fernsy is added to Claude Desktop again

#### Scenario: Nightly build
- **WHEN** the extension is built by a nightly whose version is "nightly-2026-10-25"
- **THEN** the manifest version is a semantic version such as "0.0.118"
