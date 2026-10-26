#!/bin/bash
# Builds the Apple TV app with its UI tests and runs them on the tvOS simulator, against the
# demo server (see DEVELOPMENT.md › Apple TV). About 30 s when everything is built.
#
#   scripts/tv-uitest.sh              # build at background priority, then test
#   scripts/tv-uitest.sh --no-build   # test the last build
#   scripts/tv-uitest.sh -only-testing:FernsyTVUITests/PlayerUITests   # further xcodebuild arguments
#
# On a failure xcodebuild would otherwise run `simctl diagnose`, which takes many minutes;
# -collect-test-diagnostics never skips it. A test that hangs is stopped after 2 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/tv"
DEVICE_NAME="Apple TV 4K (3rd generation)"
BUILD=1
if [ "${1:-}" = "--no-build" ]; then BUILD=0; shift; fi

DEVICE="$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | grep -v "at 1080p" | head -1 \
    | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
if [ -z "$DEVICE" ]; then
    echo "No '$DEVICE_NAME' simulator: install the tvOS runtime (xcodebuild -downloadPlatform tvOS)." >&2
    exit 1
fi
ARGS=(-project "$ROOT/Fernsy.xcodeproj" -scheme "Fernsy TV" -destination "platform=tvOS Simulator,id=$DEVICE"
      -derivedDataPath "$DD")

if [ "$BUILD" = 1 ]; then
    echo "▸ build-for-testing"
    taskpolicy -b xcodebuild build-for-testing "${ARGS[@]}" -quiet
fi
echo "▸ UI tests on $DEVICE_NAME ($DEVICE)"
xcodebuild test-without-building "${ARGS[@]}" -quiet -collect-test-diagnostics never \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 120 "$@"
echo "✔ Apple TV UI tests passed"
