#!/bin/bash
# Builds the Apple TV app ("Fernsy Dev", debug) at background priority, starts the tvOS
# simulator with its window and launches the app against the demo server.
#
#   scripts/tv-run.sh                                   # build, run with the demo account
#   scripts/tv-run.sh --log build/devtest/tv.log IPTV_AUTOPLAY=live:101 IPTV_SOUND=1
#   scripts/tv-run.sh --no-build IPTV_MCP=1             # debug MCP server on port 52325
#
# Extra KEY=value arguments go into the app's environment (as SIMCTL_CHILD_KEY) and replace
# the demo defaults below. Screenshots: xcrun simctl io <device> screenshot <file>.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/tv"
APP="$DD/Build/Products/Debug-appletvsimulator/FernsyTV.app"
BUNDLE=de.mobilistics.fernsy.dev
DEVICE_NAME="Apple TV 4K (3rd generation)"
LOG="$ROOT/build/tv-run.log"
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

# The simulator: the first available Apple TV 4K (3rd generation) with tvOS 27, by id.
DEVICE="$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | grep -v "at 1080p" | head -1 \
    | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
if [ -z "$DEVICE" ]; then
    echo "No '$DEVICE_NAME' simulator: install the tvOS runtime (xcodebuild -downloadPlatform tvOS)." >&2
    exit 1
fi

if [ "$BUILD" = 1 ]; then
    taskpolicy -b xcodebuild -project "$ROOT/Fernsy.xcodeproj" -scheme "Fernsy TV" -configuration Debug \
        -destination "platform=tvOS Simulator,id=$DEVICE" -derivedDataPath "$DD" build -quiet
fi

xcrun simctl boot "$DEVICE" 2>/dev/null || true   # already booted is fine
# Show it: Simulator.app where it exists; Xcode 27.1 shows booted simulators itself.
open -g -a Simulator --args -CurrentDeviceUDID "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

# Demo defaults first; a later KEY=value of the same key wins (bash 3.2: no associative arrays).
PAIRS=(FERNSY_NO_KEYCHAIN=1 IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev IPTV_USER=demo
       IPTV_PASS=demo IPTV_MCPTOKEN=test "${EXTRA[@]+"${EXTRA[@]}"}")
ENVS=()
for i in "${!PAIRS[@]}"; do
    key="${PAIRS[$i]%%=*}"
    later=0
    for j in "${!PAIRS[@]}"; do [ "$j" -gt "$i" ] && [ "${PAIRS[$j]%%=*}" = "$key" ] && later=1; done
    [ "$later" = 0 ] && ENVS+=("SIMCTL_CHILD_${PAIRS[$i]}")
done

xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"   # one run per log
env "${ENVS[@]}" xcrun simctl launch --terminate-running-process --stdout="$LOG" --stderr="$LOG" "$DEVICE" "$BUNDLE" >/dev/null
echo "Fernsy Dev on $DEVICE_NAME ($DEVICE), log: $LOG"
