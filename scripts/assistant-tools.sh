#!/bin/bash
# Writes the in-app assistant's tool definitions (FernsyCore AssistantTools) to
# cloud-server/assistant-tools.js, the copy the Fernsy Cloud worker attaches to every relayed
# request (cloud-assistant). The FernsyCore tests fail while that copy is out of date.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Packages/FernsyCore"
LOG="$(mktemp)"
if ! FERNSY_WRITE_ASSISTANT_TOOLS=1 swift test --filter AssistantToolsTests/workerCopyMatches > "$LOG" 2>&1; then
    tail -30 "$LOG"; rm -f "$LOG"; exit 1
fi
rm -f "$LOG"
echo "✓ cloud-server/assistant-tools.js ($(grep -c '"type" : "function"' "$ROOT/cloud-server/assistant-tools.js") tools)"
