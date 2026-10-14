#!/bin/bash
# Deploys the demo server as the Cloudflare Worker "fernsy-demo" (workers.dev) via the API.
#
#   CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… demo-server/deploy.sh
#
# The token needs the "Edit Cloudflare Workers" permissions. Media files are not part of
# the worker; they are assets of the GitHub release "demo-media".
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
NAME=fernsy-demo
API="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$NAME"

curl -fsS -X PUT "$API" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -F 'metadata={"main_module":"worker.js","compatibility_date":"2026-10-01"};type=application/json' \
    -F "worker.js=@$DIR/worker.js;type=application/javascript+module" \
    -F "data.json=@$DIR/data.json;type=text/plain" > /dev/null
curl -fsS -X POST "$API/subdomain" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" -d '{"enabled":true,"previews_enabled":false}' > /dev/null
SUBDOMAIN=$(curl -fsS "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['subdomain'])")
echo "✓ https://$NAME.$SUBDOMAIN.workers.dev"
