## MODIFIED Requirements

### Requirement: Local server, off by default
Fernsy SHALL offer an MCP server (Streamable HTTP, JSON responses) under Settings ›
Assistenten, off by default. When on, it SHALL listen only on 127.0.0.1 at a fixed port shown
in Settings, and only while Fernsy runs. Settings SHALL show the endpoint address, a command
for Claude Code, a one-click Claude Desktop extension and, as fallback, the config entry.

#### Scenario: Switching it on
- **WHEN** the user turns on the MCP server in Settings › Assistenten
- **THEN** `http://127.0.0.1:<port>/mcp` answers MCP `initialize` requests and Settings shows how to add it to Claude

#### Scenario: Other devices
- **WHEN** another computer in the network connects to the Mac on that port
- **THEN** the connection is not accepted

## ADDED Requirements

### Requirement: Claude Desktop extension
"Zu Claude Desktop hinzufügen …" SHALL build a desktop extension (`.mcpb`) for the current
endpoint and token and open it in Claude Desktop, or let the user save it when Claude Desktop is
missing. The extension SHALL need no Node.js installation, keep the token as a sensitive
setting, forward MCP messages to the local endpoint, and answer tool calls with an explanation
while Fernsy or its server is not running.

#### Scenario: Adding Fernsy to Claude Desktop
- **WHEN** the user chooses "Zu Claude Desktop hinzufügen …" with Claude Desktop installed
- **THEN** Claude Desktop shows its install dialog for "Fernsy", and after installing, Claude can use Fernsy's tools

#### Scenario: Fernsy closed
- **WHEN** Claude calls a Fernsy tool while Fernsy is not running
- **THEN** the call returns that Fernsy must be open with the MCP server switched on

#### Scenario: New token
- **WHEN** the user creates a new token in Fernsy
- **THEN** the installed extension is refused until it is installed again or given the new token
