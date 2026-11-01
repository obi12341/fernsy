# Proposal

## Why

Fernsy already has the tools an assistant needs: the Mac's MCP server offers 21 of them (find
channels, what's on, search the guide, schedule recordings, play, seek, scenes), used today from
Claude Desktop. Users without Claude Desktop, and everyone on iPhone, iPad and Apple TV, cannot
ask Fernsy "what's on tonight?" or "record the Tatort". An assistant inside the apps makes that
the normal way to use Fernsy, and it gives Fernsy Cloud a reason to subscribe on every device,
not only for people who record on a Mac.

## What Changes

- **Assistant in every app** (Mac, iPhone/iPad, Apple TV): the user types or dictates a request,
  the assistant answers briefly and acts — plays a channel or film, opens a page, schedules a
  recording (where the device records), searches the guide. On the Apple TV it is an overlay
  with one request, one answer and one action, entered by dictation in a text field.
- **Part of Fernsy Cloud**: the assistant is included in the existing subscription (price
  unchanged at 2.99 € for now, pricing revisited later) with a monthly allowance of requests.
- **Offered on every platform**: iPad, iPhone and Apple TV offer the subscription without a Mac
  (the "offer only with a Mac" rule goes), and the offer names both parts: the assistant on all
  devices, the recordings cloud with a Mac.
- **Relay on the Fernsy Cloud server**: the Cloudflare worker forwards requests to the language
  model with Fernsy's key, after checking the subscription and the allowance. The model gets all
  data a request needs (channels, guide, library, favourites, recently watched); the tools run
  in the app, where that data lives.
- **Abuse protection on the server**, not only in the system prompt: subscription check on every
  request, allowance and rate limit per account, Fernsy's tools always attached, short answers,
  a cap on tool rounds.
- **Consent once**: before the first request the app says which data goes to which provider, and
  the privacy page says the same.

## Capabilities

### New Capabilities

- `assistant`: the in-app assistant on all three apps — input, answers, actions, limits as the
  user sees them, consent.

### Modified Capabilities

- `recording-cloud`: the subscription includes the assistant; "Offer only with a Mac" is removed.
- `cloud-server`: a relay for assistant requests with subscription check, allowance and rate
  limit; "No keys or readable content" states what the relay may see and that it keeps none of
  it.

## Impact

- Provider: OpenRouter (one key, models switchable in the worker), default model Claude Haiku.
- FernsyCore: tool definitions shared by all apps (from the Mac's MCP tools), the assistant
  conversation loop, the relay client.
- Mac, Apple TV, iOS: tool execution against each app's model, the assistant UI, the consent
  screen, the offer in Settings › Fernsy Cloud.
- `cloud-server/`: a new endpoint, allowance counting in D1, the model provider's key as a worker
  secret.
- Website privacy page (German and English); App Store privacy details (data used by a third
  party AI provider).

## Out of scope

- Pricing and the final allowance (provisional numbers here, decided later).
- Bring your own key, an on-device model, a separate assistant subscription.
- Voice output, a continuous microphone, the Siri button on the Apple TV remote.
- Changing the MCP server for Claude Desktop (it stays as it is).
