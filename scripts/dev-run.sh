#!/bin/bash
# Builds the debug app ("Fernsy Dev", de.mobilistics.fernsy.dev) at background priority and
# starts it in the background against the demo server, next to the installed Fernsy.
#
#   scripts/dev-run.sh                          # build, start with the demo account
#   scripts/dev-run.sh --log /tmp/dev.log IPTV_AUTOPLAY=live:101 IPTV_SOUND=1
#   scripts/dev-run.sh --no-build IPTV_COPIEDACCOUNT=<folder>
#
# The build runs with `taskpolicy -b`, so playback in the installed app keeps the CPU. The app
# starts with `open -g`: it does not come to the front (and stays quiet, see DEVELOPMENT.md).
# Extra KEY=value arguments go into its environment; they replace the demo defaults below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/dd/Build/Products/Debug/Fernsy.app"
LOG="$ROOT/build/dev-run.log"
BUILD=1
EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --log) LOG="$2"; shift 2 ;;
        --no-build) BUILD=0; shift ;;
        *=*) EXTRA+=("$1"); shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if pgrep -f "/Applications/Fernsy.app/Contents/MacOS/Fernsy" >/dev/null; then
    echo "Installed Fernsy is running: test only against the demo server (its stream slot is the user's)."
fi

if [ "$BUILD" = 1 ]; then
    taskpolicy -b xcodebuild -project "$ROOT/Fernsy.xcodeproj" -scheme Fernsy -configuration Debug \
        -destination "platform=macOS,arch=arm64" -derivedDataPath "$ROOT/build/dd" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
fi

# Demo defaults first; a later KEY=value of the same key wins (bash 3.2: no associative arrays).
PAIRS=(FERNSY_NO_KEYCHAIN=1 IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev IPTV_USER=demo
       IPTV_PASS=demo IPTV_MCP=1 IPTV_MCPTOKEN=test "${EXTRA[@]+"${EXTRA[@]}"}")
COPIED=0
for pair in "${PAIRS[@]}"; do [ "${pair%%=*}" = IPTV_COPIEDACCOUNT ] && COPIED=1; done
ARGS=()
for i in "${!PAIRS[@]}"; do
    key="${PAIRS[$i]%%=*}"
    # A copied account opens offline instead of the demo login.
    if [ "$COPIED" = 1 ]; then case "$key" in IPTV_SERVER|IPTV_USER|IPTV_PASS) continue ;; esac; fi
    later=0
    for j in "${!PAIRS[@]}"; do [ "$j" -gt "$i" ] && [ "${PAIRS[$j]%%=*}" = "$key" ] && later=1; done
    [ "$later" = 0 ] && ARGS+=(--env "${PAIRS[$i]}")
done
mkdir -p "$(dirname "$LOG")"
open -g -n "${ARGS[@]}" --stdout "$LOG" --stderr "$LOG" "$APP" --args -ApplePersistenceIgnoreState YES
sleep 1
echo "Fernsy Dev started (pid $(pgrep -nf "$APP/Contents/MacOS/Fernsy" || echo ?)), log: $LOG"
