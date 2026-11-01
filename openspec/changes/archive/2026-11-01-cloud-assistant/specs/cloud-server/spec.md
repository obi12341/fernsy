## ADDED Requirements

### Requirement: Assistant relay
The server SHALL forward assistant requests of subscribed accounts to the language model with
Fernsy's provider key, which apps never receive, attaching Fernsy's own system prompt and tools
and capping answer length and tool rounds. It SHALL count requests per account against a
monthly allowance and a short-term rate, and refuse requests over either or without an active
subscription, naming the reason.

#### Scenario: Allowance used up
- **WHEN** an account has used its monthly allowance and sends another request
- **THEN** the server refuses it without calling the model and names the date the allowance renews

#### Scenario: Ended subscription
- **WHEN** an account whose subscription ended sends a request
- **THEN** the server refuses it without calling the model

#### Scenario: Tool definitions from the client
- **WHEN** a request carries its own system prompt or tools
- **THEN** the server ignores them and uses Fernsy's

## MODIFIED Requirements

### Requirement: No keys or readable content
The server SHALL NOT receive, store or log encryption keys, access secrets, titles, channel
names or other readable recording details, and it SHALL NOT log signed URLs. Assistant requests
pass through the server readable, as the model needs them; the server SHALL NOT store or log
their content, only the account id, time, token counts and outcome. Its logs SHALL hold only
account ids, recording ids, sizes, times, token counts and outcomes.

#### Scenario: Server logs
- **WHEN** a recording is uploaded, streamed and deleted
- **THEN** the server's logs for it contain only ids, sizes, times and outcomes

#### Scenario: Assistant request
- **WHEN** an assistant request about a channel is relayed
- **THEN** the server's logs and database hold the account id, time, token counts and outcome, and no part of the request or answer

#### Scenario: Stored credentials
- **WHEN** the server's database is read
- **THEN** it holds only a hash of each account's access secret, from which the secret cannot be recovered
