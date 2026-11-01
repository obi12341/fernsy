#!/bin/bash
# Prints the duration of every UI test in a result bundle, grouped by class and slowest first,
# with the total (faster-ui-tests). Several bundles are added up, so the host run (playback
# classes) and the VM run (the rest) give one table.
#
#   scripts/uitest-times.sh build/tv/Logs/uitest-*.xcresult
#   scripts/uitest-times.sh --csv a.xcresult b.xcresult > times.csv
set -euo pipefail

CSV=0
if [ "${1:-}" = "--csv" ]; then CSV=1; shift; fi
[ $# -gt 0 ] || { echo "usage: scripts/uitest-times.sh [--csv] <result bundle>…" >&2; exit 2; }

for bundle in "$@"; do
    xcrun xcresulttool get test-results tests --path "$bundle"
done | python3 -c '
import json, sys
csv = sys.argv[1] == "1"
decoder, text, rows = json.JSONDecoder(), sys.stdin.read(), []
def walk(node, suite=None):
    kind = node.get("nodeType")
    if kind == "Test Suite": suite = node.get("name")
    if kind == "Test Case":
        rows.append((suite or "?", node.get("name", "?"), node.get("durationInSeconds") or 0.0, node.get("result", "?")))
    for child in node.get("children", []): walk(child, suite)
position = 0
while position < len(text):
    while position < len(text) and text[position].isspace(): position += 1
    if position >= len(text): break
    data, position = decoder.raw_decode(text, position)
    for node in data.get("testNodes", []): walk(node)
if csv:
    print("class,test,seconds,result")
    for suite, test, seconds, result in rows: print(f"{suite},{test},{seconds:.1f},{result}")
    sys.exit(0)
classes = {}
for suite, test, seconds, result in rows: classes.setdefault(suite, []).append((test, seconds, result))
for suite, tests in sorted(classes.items(), key=lambda item: -sum(t[1] for t in item[1])):
    print(f"{sum(t[1] for t in tests):7.1f} s  {suite} ({len(tests)})")
    for test, seconds, result in sorted(tests, key=lambda t: -t[1]):
        mark = "" if result == "Passed" else f"  [{result}]"
        print(f"           {seconds:6.1f} s  {test}{mark}")
print(f"{sum(r[2] for r in rows):7.1f} s  total, {len(rows)} tests")
' "$CSV"
