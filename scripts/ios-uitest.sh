#!/bin/bash
# Builds the iPhone and iPad app with its UI tests and runs them on the iOS simulator, against the
# demo server (see DEVELOPMENT.md › iPhone and iPad).
#
#   scripts/ios-uitest.sh              # build at background priority, then test
#   scripts/ios-uitest.sh --no-build   # test the last build
#   scripts/ios-uitest.sh "-only-testing:Fernsy iOS UITests/FernsyiOSUITests/testFilmPagePlays"   # further xcodebuild arguments
#
# On a failure xcodebuild would otherwise run `simctl diagnose`, which takes many minutes;
# -collect-test-diagnostics never skips it. A test that hangs is stopped after 2 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/ios"
DEVICE_NAME="${DEVICE_NAME:-iPhone 18 Pro}"
BUILD=1
if [ "${1:-}" = "--no-build" ]; then BUILD=0; shift; fi

DEVICE="$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | head -1 \
    | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
if [ -z "$DEVICE" ]; then
    echo "No '$DEVICE_NAME' simulator: install the iOS runtime (xcodebuild -downloadPlatform iOS)." >&2
    exit 1
fi
ARGS=(-project "$ROOT/Fernsy.xcodeproj" -scheme "Fernsy iOS" -destination "platform=iOS Simulator,id=$DEVICE"
      -derivedDataPath "$DD")

if [ "$BUILD" = 1 ]; then
    echo "▸ build-for-testing"
    taskpolicy -b xcodebuild build-for-testing "${ARGS[@]}" -quiet
fi
echo "▸ UI tests on $DEVICE_NAME ($DEVICE)"
RESULT="$DD/Logs/uitest-$(date +%Y%m%d-%H%M%S).xcresult"
if ! xcodebuild test-without-building "${ARGS[@]}" -quiet -collect-test-diagnostics never -resultBundlePath "$RESULT" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 120 "$@"; then
    # -quiet leaves out why a test failed: print the failure messages (first lines) from the bundle.
    xcrun xcresulttool get test-results tests --path "$RESULT" 2>/dev/null | python3 -c '
import json, sys
def walk(node, name=""):
    if node.get("nodeType") == "Test Case": name = node.get("name", "")
    if node.get("nodeType") == "Failure Message": print(f"✘ {name}: " + "\n    ".join(node.get("name", "").splitlines()[:3]))
    for child in node.get("children", []): walk(child, name)
for node in json.load(sys.stdin).get("testNodes", []): walk(node)' || true
    exit 65
fi
echo "✔ iPhone and iPad UI tests passed"
