#!/bin/bash
# Deploys Fernsy Control (control-server) through the Cloudflare API, like cloud-server/deploy.sh:
# D1 database with schema.sql, the worker, the daily cleanup cron and the workers.dev address.
# Safe to run again.
#
#   CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… control-server/deploy.sh            # dev
#   CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… control-server/deploy.sh --prod     # production
#
# dev  = worker and D1 fernsy-control-dev.
# prod = worker and D1 fernsy-control.
# The token needs: Workers Scripts Write, D1 Write.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=dev
for arg in "$@"; do
    case "$arg" in
        --prod) TARGET=prod ;;
        *) echo "unknown argument $arg" >&2; exit 2 ;;
    esac
done
if [ "$TARGET" = prod ]; then NAME=fernsy-control; else NAME=fernsy-control-dev; fi

API="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID"
AUTH="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
cf() { curl -fsS -H "$AUTH" "$@"; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

DB_ID="$(cf "$API/d1/database?name=$NAME" | json "next((x['uuid'] for x in d['result'] if x['name']=='$NAME'), '')")"
if [ -z "$DB_ID" ]; then
    DB_ID="$(cf -X POST "$API/d1/database" -H "Content-Type: application/json" -d "{\"name\":\"$NAME\"}" | json "d['result']['uuid']")"
fi
python3 -c "import json,sys; print(json.dumps({'sql': open(sys.argv[1]).read()}))" "$DIR/schema.sql" \
    | cf -X POST "$API/d1/database/$DB_ID/query" -H "Content-Type: application/json" --data-binary @- > /dev/null

METADATA="$(DB_ID="$DB_ID" python3 -c 'import json, os; print(json.dumps({"main_module": "worker.js", "compatibility_date": "2026-10-01", "bindings": [{"type": "d1", "name": "DB", "id": os.environ["DB_ID"]}]}))')"
cf -X PUT "$API/workers/scripts/$NAME" \
    -F "metadata=$METADATA;type=application/json" \
    -F "worker.js=@$DIR/worker.js;type=application/javascript+module" > /dev/null
cf -X PUT "$API/workers/scripts/$NAME/schedules" -H "Content-Type: application/json" -d '[{"cron":"41 3 * * *"}]' > /dev/null
cf -X POST "$API/workers/scripts/$NAME/subdomain" -H "Content-Type: application/json" \
    -d '{"enabled":true,"previews_enabled":false}' > /dev/null
SUBDOMAIN="$(cf "$API/workers/subdomain" | json "d['result']['subdomain']")"
echo "✓ https://$NAME.$SUBDOMAIN.workers.dev (D1 $DB_ID)"
