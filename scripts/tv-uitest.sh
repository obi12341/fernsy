#!/bin/bash
# Builds the Apple TV app with its UI tests and runs them on the tvOS simulator, against the
# demo server (see DEVELOPMENT.md › Apple TV). All tests take about 25 min on a CI runner and less
# on a Mac; CI runs them in 3 shards in parallel (tvos-uitest-shards).
#
#   scripts/tv-uitest.sh              # build at background priority, then test
#   scripts/tv-uitest.sh --no-build   # test the last build
#   scripts/tv-uitest.sh --shard 2/3  # only the second of three parts (each test class in one part)
#   scripts/tv-uitest.sh --list 3     # print the classes of each of three parts, run nothing
#   scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/PlayerUITests"   # further xcodebuild arguments
#
# On a failure xcodebuild would otherwise run `simctl diagnose`, which takes many minutes;
# -collect-test-diagnostics never skips it. A test that hangs is stopped after 2 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/tv"
DEVICE_NAME="${DEVICE_NAME:-Apple TV 4K (3rd generation)}"   # another simulator: DEVICE_NAME="…"
BUILD=1
SHARD=""
LIST=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) BUILD=0; shift ;;
        --shard) SHARD="$2"; shift 2 ;;
        --list) LIST="$2"; shift 2 ;;
        *) break ;;
    esac
done

# The UI test classes in parts (tvos-uitest-shards): found in the sources, so a new class needs no
# list; greedy by test count (most first, ties by name) into the part with the fewest tests, which
# every shard computes the same way. Prints "part<TAB>class<TAB>tests" lines.
parts() {
    python3 - "$ROOT/FernsyTVUITests" "$1" <<'PY'
import pathlib, re, sys
folder, n = pathlib.Path(sys.argv[1]), int(sys.argv[2])
classes = {}
for file in sorted(folder.glob("*.swift")):
    current = None
    for line in file.read_text().splitlines():
        m = re.match(r"\s*(?:final\s+)?class\s+(\w+)\s*:\s*(FernsyUITestCase|XCTestCase)\b", line)
        if m:
            current = None if m.group(1) == "FernsyUITestCase" else m.group(1)
            if current: classes[current] = 0
        elif current and re.match(r"\s*func\s+test\w*\s*\(", line):
            classes[current] += 1
if not classes:
    sys.exit("no UI test classes found in " + str(folder))
load = [0] * n
for name, tests in sorted(classes.items(), key=lambda c: (-c[1], c[0])):
    part = load.index(min(load))
    load[part] += tests
    print(f"{part + 1}\t{name}\t{tests}")
PY
}

if [ -n "$LIST" ]; then
    parts "$LIST" | sort -n -k1,1 -k2,2 | awk -F'\t' '{ count[$1] += $3; print "part " $1 ": " $2 " (" $3 ")" }
        END { for (p in count) print "part " p " total: " count[p] " tests" }'
    exit 0
fi
ONLY=()
if [ -n "$SHARD" ]; then
    INDEX="${SHARD%/*}"; COUNT="${SHARD#*/}"
    while IFS=$'\t' read -r part name _; do
        [ "$part" = "$INDEX" ] && ONLY+=("-only-testing:Fernsy TV UITests/$name")
    done < <(parts "$COUNT")
    if [ ${#ONLY[@]} -eq 0 ]; then
        echo "Shard $SHARD has no test classes." >&2
        exit 1
    fi
    echo "▸ shard $SHARD: ${#ONLY[@]} classes"
fi

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
RESULT="$DD/Logs/uitest-$(date +%Y%m%d-%H%M%S).xcresult"
if ! xcodebuild test-without-building "${ARGS[@]}" -quiet -collect-test-diagnostics never -resultBundlePath "$RESULT" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 120 \
    "${ONLY[@]+"${ONLY[@]}"}" "$@"; then
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
echo "✔ Apple TV UI tests passed"
