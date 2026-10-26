#!/bin/bash
# Copies data of the installed Fernsy into the debug build's container ("Fernsy Dev"), for
# tests with real data. The installed app's container is only read.
#
#   scripts/dev-copy-prod.sh --list             # account folders, numbered
#   scripts/dev-copy-prod.sh --account 3        # copies folder 3 as "copied-3"
#   scripts/dev-copy-prod.sh --settings         # copies library, live, track and recording settings
#
# Then: scripts/dev-run.sh --no-build IPTV_COPIEDACCOUNT=copied-3 (offline: cached catalog,
# guide and recordings list, no requests to the provider, no streams).
#
# Never copied: keychain items (accounts and passwords stay in the installed app), the MCP
# token, update settings, Jellyfin device ids. Scheduled or running recordings become
# "skipped" in the copy, so the debug build never records for the user. Folders are listed by
# number and copied under a neutral name, because their names contain the account's username.
set -euo pipefail

PROD="$HOME/Library/Containers/de.mobilistics.fernsy/Data/Library"
DEV="$HOME/Library/Containers/de.mobilistics.fernsy.dev/Data/Library"
SRC="$PROD/Application Support/Fernsy"
DST="$DEV/Application Support/Fernsy"

if [ ! -d "$DEV" ]; then
    echo "No container for Fernsy Dev yet: start it once (scripts/dev-run.sh) and run this again." >&2
    exit 1
fi

# Xtream account folders only (Jellyfin folders hold no data worth copying without a session).
folders() { find "$SRC" -mindepth 1 -maxdepth 1 -type d ! -name 'jellyfin-*' -exec basename {} \; | sort; }

case "${1:-}" in
--list)
    n=0
    while IFS= read -r folder; do
        n=$((n + 1))
        dir="$SRC/$folder"
        what=""
        [ -f "$dir/get_live_streams.json" ] && what="$what catalog"
        [ -d "$dir/epg" ] && what="$what guide"
        [ -f "$dir/recordings.json" ] && what="$what recordings"
        # The beginning names the server; the username follows at the end and is not shown.
        echo "$n: ${folder:0:14}… ($(du -sh "$dir" | cut -f1),$what)"
    done < <(folders)
    ;;
--account)
    index="${2:?--account needs a number from --list}"
    folder="$(folders | sed -n "${index}p")"
    [ -n "$folder" ] || { echo "No folder $index (see --list)." >&2; exit 1; }
    target="$DST/copied-$index"
    rm -rf "$target"
    mkdir -p "$DST"
    cp -R "$SRC/$folder" "$target"
    if [ -f "$target/recordings.json" ]; then
        python3 -I - "$target/recordings.json" <<'EOF'
import json, sys
path = sys.argv[1]
recordings = json.load(open(path))
changed = 0
for r in recordings:
    if r.get("status") in ("scheduled", "recording"):
        r["status"] = "skipped"
        r["error"] = "Kopie aus Fernsy"
        changed += 1
json.dump(recordings, open(path, "w"))
print(f"{len(recordings)} recordings, {changed} scheduled or running ones set to skipped")
EOF
    fi
    echo "Copied as copied-$index: scripts/dev-run.sh --no-build IPTV_COPIEDACCOUNT=copied-$index"
    ;;
--settings)
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    defaults export "$PROD/Preferences/de.mobilistics.fernsy" "$tmp/prod.plist"
    python3 -I - "$tmp/prod.plist" "$tmp/dev.plist" <<'EOF'
import plistlib, sys
keep = ("library.", "live.", "liveMode", "tracks.", "recording.", "timeshift", "appearance", "watched.",
        "jellyfin.sort.", "menuBar.enabled")
prod = plistlib.load(open(sys.argv[1], "rb"))
dev = {k: v for k, v in prod.items() if k.startswith(keep)}
plistlib.dump(dev, open(sys.argv[2], "wb"))
print(f"{len(dev)} of {len(prod)} settings copied")
EOF
    defaults import "$DEV/Preferences/de.mobilistics.fernsy.dev" "$tmp/dev.plist"
    ;;
*)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
