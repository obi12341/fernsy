#!/bin/bash
# Runs the FernsyCore tests on macOS and builds the package for tvOS (see DEVELOPMENT.md ›
# Tests and FernsyCore).
#
#   scripts/test.sh             # macOS tests + tvOS build
#   scripts/test.sh --tvos-sim  # also run the tests on a tvOS simulator (needs the tvOS runtime)
#
# Exits non-zero as soon as a step fails. Builds go to build/core (git-ignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Packages/FernsyCore"
DD="$ROOT/build/core"

run() {
    echo "▸ $*"
    # -quiet keeps the log short; failing tests and errors are still printed.
    xcodebuild "$@" -scheme FernsyCore -derivedDataPath "$DD" -quiet
}

run test -destination 'platform=macOS'
run build -destination 'generic/platform=tvOS Simulator'

if [ "${1:-}" = "--tvos-sim" ]; then
    DEVICE="$(xcrun simctl list devices available | grep -m1 -o 'Apple TV[^(]*' | sed 's/ *$//' || true)"
    if [ -z "$DEVICE" ]; then
        echo "No tvOS simulator: install the runtime with 'xcodebuild -downloadPlatform tvOS'." >&2
        exit 1
    fi
    run test -destination "platform=tvOS Simulator,name=$DEVICE"
fi
echo "✔ FernsyCore tests passed"
