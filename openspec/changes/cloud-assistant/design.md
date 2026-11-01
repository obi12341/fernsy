## Context

- The Mac's MCP server (`Fernsy/MCP/MCPTools.swift`) defines 21 tools with JSON schemas and runs
  them against `AppModel` (channels, guide, search, recordings, playback, scenes). The Apple TV has
  a debug-only MCP server; iOS has none.
- The Fernsy Cloud worker (`cloud-server/worker.js`, Cloudflare Worker with D1 and R2) knows
  accounts by `Authorization: Key <accountId>:<secret>` (hash stored), checks subscriptions with
  Apple's App Store Server API (`apple.js`) and keeps a storage quota.
- Fernsy Cloud is still hidden behind `FERNSY_CLOUD`; the assistant ships with it.
- Decisions taken with the user (2026-11-01): a relay of our own (not BYOK, not on-device); part
  of the Fernsy Cloud subscription at the current price, pricing later; offered on every platform;
  the model gets all data a request needs.

## Goals / Non-Goals

**Goals:**
- One assistant behaviour on Mac, iPhone/iPad and Apple TV, built on one set of tool definitions.
- Costs bounded per account by the server, whatever the client sends.
- Consent before data leaves the device; nothing of the content kept on the server.

**Non-Goals:** pricing, voice output, a separate subscription, changes to the external MCP server.

## Decisions

### 1. The relay holds the key, the prompt and the tools; the app runs the tools
```
App --(messages, context)--> Worker: subscription? allowance? rate?
                                     + system prompt + tool definitions + provider key
                             Worker --> model
App <--(tool_use)----------- Worker <-- model
App runs the tool on its own model (AppModel / TVModel), sends tool_result
 ... up to N rounds ...
App <--(answer, action)----- Worker
```
The worker is stateless per round: the app sends the conversation so far each time. Tool
definitions and the system prompt live on the server (versioned with the app's protocol version),
so a modified client cannot turn the relay into a general chatbot.
Rejected: tools defined in the request (lets any client send any tools); the server running tools
(the guide, library and playback live in the app, and the server must not hold readable catalogs).

### 2. Provider and model: OpenRouter
The relay calls OpenRouter's OpenAI-compatible chat completions API (tools as `functions`,
`tool_calls` in answers) with one key, stored as the worker secret `OPENROUTER_API_KEY`
(decided with the user, 2026-11-01; the key comes from the user's existing OpenRouter account).
Default model: Claude Haiku (`anthropic/claude-haiku-5.5` on OpenRouter), fast enough for a
remote-control interaction and among the cheapest capable models. The model id is a worker
setting, so it can change without an app update; OpenRouter's cache control for Anthropic models
keeps the system prompt and tool definitions, the largest part of each request, cached. A spending
limit can be set on the key in OpenRouter.
Rejected: Anthropic's Messages API directly (a second account and key, no switching models
without code); several providers in the relay (OpenRouter already routes to them); a larger model
by default (cost per request within 2.99 €).

### 3. Abuse protection on the server
- Subscription check per request (cached for minutes, as the storage endpoints do).
- Allowance per account and calendar month, counted in D1 at the start of a user turn (tool
  rounds of the same turn do not count again); a short-term rate per minute.
- `max_tokens` per round and a cap on tool rounds per turn; a size cap on each request body.
- Only Fernsy's tools; the system prompt declines other topics in one sentence.
Provisional numbers until pricing: 300 requests a month, 10 a minute, 800 output tokens per round,
8 tool rounds per turn. They are worker settings.
Rejected: relying on the system prompt alone (it can be talked around; the limits cannot).

### 4. Tool definitions in FernsyCore, execution per platform
The MCP tools' names, descriptions and schemas move to FernsyCore (`AssistantTools`), used by the
Mac's MCP server and the assistant alike, and exported to the worker as JSON at build time
(`scripts/assistant-tools.sh`) so server and apps share one source. Each app implements the
calls it supports: the Mac all, Apple TV all but scene search on Jellyfin subtitles where missing,
iOS without recording tools (iOS does not record). A call the platform lacks returns an error the
model can explain.
Rejected: a second, hand-written tool list for the assistant (would drift from MCP).

### 5. Actions that change things
Playing, opening pages and searching run at once. Scheduling a recording runs at once (it can be
cancelled). Cancelling a recording and anything that deletes needs the user's confirmation in the
app before the tool runs; deleting cloud recordings is not offered as a tool.
Rejected: confirmation for every action (the assistant would feel slower than the remote).

### 6. Text from the guide is data, not instructions
Show titles and descriptions come from IPTV providers and could contain text aimed at the model.
The system prompt says tool results are data; the confirmation rule (decision 5) keeps such text
from cancelling or deleting anything.

### 7. Platforms and order
Mac and iPhone/iPad first (text field with system dictation, a panel with the session's
conversation), then the Apple TV (an overlay: one dictated request, the answer, the action; opened
from a button on Start and in the player's menu). The assistant entry shows only with the
subscription; without it, it offers Fernsy Cloud.

### 8. Consent and privacy
A consent screen before the first request per device, naming OpenRouter and the model's
provider (Anthropic) and the data
sent (request, conversation, the catalog parts a request needs, favourites, recently watched).
Stored per device (UserDefaults key `assistant.consent`, not synced: each device asks once),
revocable in Settings. The worker logs only account id, time, token counts and outcome. The
privacy pages (German, English) and the App Store privacy details get the same text.

### 9. Offer on every platform
The Mac marker check before offering the subscription goes. The offer text names both parts:
"Assistant on all your devices" and "Recordings from Fernsy on your Mac in the cloud".

## Risks / Trade-offs

- [Costs exceed the price for heavy users] → the allowance caps them; usage per account is logged
  as token counts, which the pricing work later uses.
- [Provider outage] → the assistant says it is unavailable; nothing else in Fernsy depends on it.
- [Apple TV dictation unavailable (turned off by the user)] → typing with the on-screen keyboard
  or the iPhone keyboard still works.
- [The model calls a tool with wrong arguments] → tools validate and return errors the model can
  correct; actions with effects are limited (decision 5).
- [Readable requests pass the server] → stated in the spec and the consent; never stored or logged.

## Migration Plan

Behind `FERNSY_CLOUD` with the rest of Fernsy Cloud; worker endpoint deployed to the dev
deployment first (`Dev` token), tested with the demo account, then production. Rollback: turn the
endpoint off in the worker's settings; the apps show the assistant as unavailable.

## Open Questions

- Final allowance and price (pricing work after this change).
- Whether the Apple TV entry also goes on the remote's Play/Pause long press (UX test on the
  device).
