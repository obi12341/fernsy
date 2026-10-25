#!/bin/bash
# Collects the release notes of a release or nightly from the commits' trailers:
#
#   Release-Note-de: Aufnahmen lassen sich während einer Aufnahme wieder öffnen.
#   Release-Note-en: Recordings open again while a recording runs.
#
#   scripts/release-notes.sh release|nightly <sha> <out-dir>
#
# The range is the previous v* tag..sha for a release, the last v* tag..sha for a nightly.
# Writes <out-dir>/notes-de.txt and notes-en.txt (one note per line, oldest first, no
# duplicates). A language without trailers falls back to the commit subjects (without task
# marks, archives and merges) and gets a <out-dir>/notes-<lang>.fallback marker; for a
# release that is a warning in the run.
set -euo pipefail

CHANNEL=$1 SHA=$2 OUT=$3
if [ "$CHANNEL" = "nightly" ]; then
    BASE=$(git describe --tags --match 'v[0-9]*' --abbrev=0 "$SHA" 2>/dev/null || true)
else
    BASE=$(git describe --tags --match 'v[0-9]*' --abbrev=0 "$SHA^" 2>/dev/null || true)
fi
RANGE="${BASE:+$BASE..}$SHA"
mkdir -p "$OUT"

for LANG_CODE in de en; do
    FILE="$OUT/notes-$LANG_CODE.txt"
    rm -f "$OUT/notes-$LANG_CODE.fallback"
    git log --reverse --format="%(trailers:key=Release-Note-$LANG_CODE,valueonly,unfold,separator=%x0A)" "$RANGE" |
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | awk '!seen[$0]++' > "$FILE"
    if [ ! -s "$FILE" ]; then
        if [ "$CHANNEL" = "release" ]; then
            echo "::warning::No Release-Note-$LANG_CODE trailers since ${BASE:-the beginning} – falling back to commit subjects"
        fi
        git log --reverse --no-merges --format='%s' "$RANGE" | grep -vE '^(Mark|Archive) ' > "$FILE" || true
        touch "$OUT/notes-$LANG_CODE.fallback"
    fi
done
