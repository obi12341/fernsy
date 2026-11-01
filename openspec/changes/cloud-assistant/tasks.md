# Tasks

Tested against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
demo/demo) and the Fernsy Cloud dev deployment (`Authorization: Dev <DEV_TOKEN>`, see
`cloud-server/README.md`), with `FERNSY_CLOUD=YES` builds. UI tests without playback run in the
test VM (`scripts/vm.sh`).

## 1. Shared tools

- [x] 1.1 `AssistantTools` in FernsyCore: the MCP tools' names, descriptions and schemas, used by the Mac's MCP server unchanged in behaviour
- [x] 1.2 `scripts/assistant-tools.sh` exports them as JSON for the worker (OpenAI `functions` form); a test checks the worker's copy matches
- [x] 1.3 Tool execution on Apple TV and iOS against `TVModel` (iOS without recording tools); unit tests for argument errors

## 2. Relay (cloud-server)

- [x] 2.1 `POST /v1/assistant`: account auth, subscription check, allowance per calendar month and rate per minute in D1, request size cap
- [x] 2.2 Forward to OpenRouter's chat completions API with the server's system prompt and tools (`functions`), cache control, `max_tokens` and tool-round cap; model id and limits as worker settings
- [x] 2.3 Logs and database hold only account id, time, token counts and outcome; tests for allowance, rate, ended subscription, client-sent tools ignored
- [ ] 2.4 Deploy to the dev deployment; `deploy.sh` takes `OPENROUTER_API_KEY` like its other secrets (from the user's SOPS-encrypted LibreChat secret in gitops-admin, decrypted into the deploy only)

## 3. Apps

- [x] 3.1 FernsyCore: the conversation loop (send, run tool calls, send results, until an answer) and the relay client with refusal reasons
- [ ] 3.2 Consent screen before the first request, revocable in Settings; state per device
- [ ] 3.3 Mac: assistant panel (text field with dictation, session conversation, actions); confirmation before cancelling a recording
- [ ] 3.4 iPhone/iPad: assistant sheet (same as Mac)
- [ ] 3.5 Apple TV: overlay with one dictated request, answer and action, from Start and the player's menu
- [ ] 3.6 Settings › Fernsy Cloud on all apps: offer without the Mac check, offer text naming both parts, requests used this month

## 4. Docs and privacy

- [ ] 4.1 Website privacy page (German, English): assistant data, provider, no storage
- [ ] 4.2 DEVELOPMENT.md: relay, settings, testing the assistant against the dev deployment

## 5. Verify

- [ ] 5.1 Worker tests and `scripts/test.sh`
- [ ] 5.2 Mac dev run (host): "spiel ZDF"-style requests on the demo channels play, a recording gets scheduled, an off-topic request is declined, the allowance end shows (`IPTV_` switch or a dev worker setting for a tiny allowance)
- [ ] 5.3 UI tests: iOS sheet and Apple TV overlay with a stub relay (no model calls in CI)
- [ ] 5.4 `openspec validate --all --strict`

## Workflow follow-up

- Archive on `change/cloud-assistant`, merge into `main` and push with the user's consent. The
  feature stays hidden until Fernsy Cloud launches; release-note trailers when it ships.
