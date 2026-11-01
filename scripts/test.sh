#!/bin/bash
# Runs the Fernsy Cloud and Fernsy Control worker tests (cloud-server/test, control-server/test,
# Node 24), the FernsyCore tests on
# macOS and builds the package for tvOS (see DEVELOPMENT.md › Tests and FernsyCore).
#
#   scripts/test.sh             # macOS tests + tvOS build
#   scripts/test.sh --tvos-sim  # also run the tests on a tvOS simulator (needs the tvOS runtime)
#
# Exits non-zero as soon as a step fails. Builds go to build/core (git-ignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The workers' tests use only Node's built-ins (node:test, node:sqlite, WebCrypto).
if command -v node > /dev/null; then
    mkdir -p "$ROOT/build"
    for worker in cloud-server control-server; do
        echo "▸ node --test $worker/test"
        node --test "$ROOT"/$worker/test/*.test.js > "$ROOT/build/$worker-tests.log" 2>&1 \
            || { cat "$ROOT/build/$worker-tests.log"; exit 1; }
    done
else
    echo "▸ skipping worker tests: node is not installed"
fi

cd "$ROOT/Packages/FernsyCore"
DD="${BUILD_ROOT:-$ROOT/build}/core"   # BUILD_ROOT: build data elsewhere (scripts/vm.sh)

run() {
    echo "▸ $*"
    # -quiet keeps the log short; failing tests and errors are still printed.
    xcodebuild "$@" -scheme FernsyCore-Package -derivedDataPath "$DD" -quiet
}

run test -destination 'platform=macOS'
run build -destination 'generic/platform=tvOS Simulator'

if [ "${1:-}" = "--tvos-sim" ]; then
    # By id: device names contain parentheses ("Apple TV 4K (3rd generation)").
    DEVICE="$(xcrun simctl list devices available | grep -m1 'Apple TV' | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
    if [ -z "$DEVICE" ]; then
        echo "No tvOS simulator: install the runtime with 'xcodebuild -downloadPlatform tvOS'." >&2
        exit 1
    fi
    run test -destination "platform=tvOS Simulator,id=$DEVICE"
fi
echo "✔ FernsyCore tests passed"
