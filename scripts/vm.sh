#!/bin/bash
# Runs a command in the test VM "fernsy-dev" (Tart, macOS 27 with Xcode 27.1) instead of on this
# Mac, so simulators, test accounts and build data stay out of the host. The project folder is
# shared into the VM (~/fernsy there); build data goes to ~/build inside the VM (BUILD_ROOT), so
# host and VM builds do not overwrite each other. Results land in build/ of the shared folder.
#
#   scripts/vm.sh scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/StartUITests"
#   scripts/vm.sh scripts/ios-uitest.sh
#   scripts/vm.sh scripts/test.sh
#   scripts/vm.sh --window …     # start the VM with a window to watch the simulator
#
# Real devices (Apple TV, iPad) and anything that needs the user's signing stay on the host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM="${FERNSY_VM:-fernsy-dev}"
GRAPHICS=(--no-graphics)
if [ "${1:-}" = "--window" ]; then GRAPHICS=(); shift; fi
[ $# -gt 0 ] || { echo "usage: scripts/vm.sh [--window] <command> [args…]" >&2; exit 2; }
command -v tart >/dev/null || { echo "tart is missing (see DEVELOPMENT.md › Test VM)" >&2; exit 1; }

if ! tart list --quiet --source local 2>/dev/null | grep -qx "$VM"; then
    echo "No VM '$VM' (see DEVELOPMENT.md › Test VM)" >&2; exit 1
fi
running() { tart list --source local --format json | python3 -c "import json,sys; sys.exit(0 if any(v['Name'] == sys.argv[1] and v['State'] == 'running' for v in json.load(sys.stdin)) else 1)" "$VM"; }
if ! running; then
    echo "▸ Starting $VM"
    nohup tart run "$VM" ${GRAPHICS[@]+"${GRAPHICS[@]}"} --dir=fernsy:"$ROOT" > "$ROOT/build/vm-run.log" 2>&1 &
    tart ip "$VM" --wait 180 >/dev/null
    for _ in $(seq 1 60); do tart exec "$VM" true 2>/dev/null && break; sleep 2; done
fi

# The shared folder appears under "My Shared Files"; a link without spaces keeps scripts simple.
ARGS=$(printf '%q ' "$@")
tart exec "$VM" bash -lc "ln -sfn '/Volumes/My Shared Files/fernsy' ~/fernsy && cd ~/fernsy && BUILD_ROOT=~/build $ARGS"
