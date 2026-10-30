#!/bin/bash
# Deploys Fernsy Cloud (cloud-server) through the Cloudflare API, like demo-server/deploy.sh:
# R2 bucket, D1 database with schema.sql, the worker with its bindings and secrets, the daily
# cleanup cron and the workers.dev address. Safe to run again: existing secrets are kept.
#
#   CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… cloud-server/deploy.sh            # dev
#   CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… cloud-server/deploy.sh --prod     # production
#   … cloud-server/deploy.sh --new-s3-token    # also create the bucket-only S3 token (first deploy)
#   … cloud-server/deploy.sh --reset-db        # drop the D1 tables first (schema changes before launch)
#
# dev  = worker fernsy-cloud-dev, bucket and D1 fernsy-cloud-dev, with DEV_TOKEN.
# prod = worker fernsy-cloud,     bucket and D1 fernsy-cloud,     never a DEV_TOKEN.
#
# Optional secrets from the environment (only set when given; otherwise kept):
#   S3_KEY, S3_SECRET            R2 S3 credentials (see --new-s3-token)
#   DEV_TOKEN                    dev only (generated on first dev deploy and printed once)
#   APPSTORE_KEY                 App Store Server API key (.p8 contents)
#   APPSTORE_KEY_ID, APPSTORE_ISSUER
# The token needs: Workers Scripts Write, D1 Write, Workers R2 Storage Write, and for
# --new-s3-token Account API Tokens Write.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=dev
NEW_S3=0
RESET_DB=0
for arg in "$@"; do
    case "$arg" in
        --prod) TARGET=prod ;;
        --new-s3-token) NEW_S3=1 ;;
        --reset-db) RESET_DB=1 ;;
        *) echo "unknown argument $arg" >&2; exit 2 ;;
    esac
done
if [ "$TARGET" = prod ]; then NAME=fernsy-cloud; else NAME=fernsy-cloud-dev; fi
if [ "$TARGET" = prod ] && [ -n "${DEV_TOKEN:-}" ]; then echo "DEV_TOKEN is never set on production" >&2; exit 2; fi

API="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID"
AUTH="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
cf() { curl -fsS -H "$AUTH" "$@"; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# Bucket (an existing one answers an error that is fine here).
curl -sS -X POST "$API/r2/buckets" -H "$AUTH" -H "Content-Type: application/json" -d "{\"name\":\"$NAME\"}" > /dev/null

# D1 database and schema.
DB_ID="$(cf "$API/d1/database?name=$NAME" | json "next((x['uuid'] for x in d['result'] if x['name']=='$NAME'), '')")"
if [ -z "$DB_ID" ]; then
    DB_ID="$(cf -X POST "$API/d1/database" -H "Content-Type: application/json" -d "{\"name\":\"$NAME\"}" | json "d['result']['uuid']")"
fi
if [ "$RESET_DB" = 1 ]; then
    # Every account, subscription link and recording row goes; R2 objects are not touched.
    cf -X POST "$API/d1/database/$DB_ID/query" -H "Content-Type: application/json" \
        -d '{"sql":"DROP TABLE IF EXISTS recordings; DROP TABLE IF EXISTS subscriptions; DROP TABLE IF EXISTS users;"}' > /dev/null
fi
python3 -c "import json,sys; print(json.dumps({'sql': open(sys.argv[1]).read()}))" "$DIR/schema.sql" \
    | cf -X POST "$API/d1/database/$DB_ID/query" -H "Content-Type: application/json" --data-binary @- > /dev/null

# Secrets that exist already (none on the first deploy).
EXISTING="$(curl -sS -H "$AUTH" "$API/workers/scripts/$NAME/secrets" | json "' '.join(x['name'] for x in (d.get('result') or []))" || true)"
has() { [[ " $EXISTING " == *" $1 "* ]]; }

if [ "$NEW_S3" = 1 ]; then
    # Read and write items in this bucket only; access key id = token id, secret = SHA-256 of the value.
    PERMS="$(cf "$API/tokens/permission_groups" | json "','.join('{\"id\":\"%s\"}' % g['id'] for g in d['result'] if g['name'] in ('Workers R2 Storage Bucket Item Read','Workers R2 Storage Bucket Item Write'))")"
    TOKEN_JSON="$(cf -X POST "$API/tokens" -H "Content-Type: application/json" \
        -d "{\"name\":\"$NAME R2\",\"policies\":[{\"effect\":\"allow\",\"resources\":{\"com.cloudflare.edge.r2.bucket.${CLOUDFLARE_ACCOUNT_ID}_default_${NAME}\":\"*\"},\"permission_groups\":[$PERMS]}]}")"
    S3_KEY="$(echo "$TOKEN_JSON" | json "d['result']['id']")"
    S3_SECRET="$(echo "$TOKEN_JSON" | json "__import__('hashlib').sha256(d['result']['value'].encode()).hexdigest()")"
    export S3_KEY S3_SECRET
fi
NEW_DEV_TOKEN=""
if [ "$TARGET" = dev ] && [ -z "${DEV_TOKEN:-}" ] && ! has DEV_TOKEN; then
    export DEV_TOKEN="$(openssl rand -hex 32)"
    NEW_DEV_TOKEN="$DEV_TOKEN"
fi
if ! has S3_KEY && [ -z "${S3_KEY:-}" ]; then echo "No S3 credentials: run with --new-s3-token or set S3_KEY/S3_SECRET." >&2; exit 1; fi

METADATA="$(NAME="$NAME" DB_ID="$DB_ID" ACCOUNT="$CLOUDFLARE_ACCOUNT_ID" python3 - <<'PY'
import json, os
bindings = [
    {"type": "r2_bucket", "name": "BUCKET", "bucket_name": os.environ["NAME"]},
    {"type": "d1", "name": "DB", "id": os.environ["DB_ID"]},
    {"type": "plain_text", "name": "ACCOUNT_ID", "text": os.environ["ACCOUNT"]},
    {"type": "plain_text", "name": "BUCKET_NAME", "text": os.environ["NAME"]},
]
for name in ["S3_KEY", "S3_SECRET", "DEV_TOKEN", "APPSTORE_KEY", "APPSTORE_KEY_ID", "APPSTORE_ISSUER"]:
    if os.environ.get(name):
        bindings.append({"type": "secret_text", "name": name, "text": os.environ[name]})
print(json.dumps({"main_module": "worker.js", "compatibility_date": "2026-10-01",
                  "bindings": bindings, "keep_bindings": ["secret_text"]}))
PY
)"

cf -X PUT "$API/workers/scripts/$NAME" \
    -F "metadata=$METADATA;type=application/json" \
    -F "worker.js=@$DIR/worker.js;type=application/javascript+module" \
    -F "sigv4.js=@$DIR/sigv4.js;type=application/javascript+module" \
    -F "apple.js=@$DIR/apple.js;type=application/javascript+module" \
    -F "store.js=@$DIR/store.js;type=application/javascript+module" > /dev/null
# Sessions are gone (cloud-account-from-icloud-key); drop the secret older deploys set.
if has SESSION_KEY; then cf -X DELETE "$API/workers/scripts/$NAME/secrets/SESSION_KEY" > /dev/null; fi
cf -X PUT "$API/workers/scripts/$NAME/schedules" -H "Content-Type: application/json" -d '[{"cron":"17 3 * * *"}]' > /dev/null
cf -X POST "$API/workers/scripts/$NAME/subdomain" -H "Content-Type: application/json" \
    -d '{"enabled":true,"previews_enabled":false}' > /dev/null
SUBDOMAIN="$(cf "$API/workers/subdomain" | json "d['result']['subdomain']")"
echo "✓ https://$NAME.$SUBDOMAIN.workers.dev (D1 $DB_ID)"
if [ -n "$NEW_DEV_TOKEN" ]; then echo "DEV_TOKEN=$NEW_DEV_TOKEN   (shown once; keep it for IPTV_CLOUDTOKEN)"; fi
