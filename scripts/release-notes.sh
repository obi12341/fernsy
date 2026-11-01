#!/bin/bash
# Collects the release notes of a release or nightly from the commits' trailers:
#
#   Release-Note-de: Aufnahmen lassen sich während einer Aufnahme wieder öffnen.
#   Release-Note-en: Recordings open again while a recording runs.
#
# A later commit can withdraw an earlier commit's notes (a feature replaced before it shipped):
#
#   Release-Note-Drop: 18fcaae
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

# Commits whose notes a later commit dropped, as full hashes.
DROPPED=$(git log --format='%(trailers:key=Release-Note-Drop,valueonly,separator=%x0A)' "$RANGE" |
    sed -e 's/[[:space:]]//g' -e '/^$/d' | while read -r short; do git rev-parse --verify --quiet "$short^{commit}" || true; done)

for LANG_CODE in de en; do
    FILE="$OUT/notes-$LANG_CODE.txt"
    rm -f "$OUT/notes-$LANG_CODE.fallback"
    # One "@@<hash>" line per commit, then its notes; the notes of dropped commits are left out.
    git log --reverse --format="@@%H%n%(trailers:key=Release-Note-$LANG_CODE,valueonly,unfold,separator=%x0A)" "$RANGE" |
        awk -v dropped="$DROPPED" 'BEGIN { n = split(dropped, d, "\n"); for (i = 1; i <= n; i++) skip[d[i]] = 1 }
            /^@@/ { commit = substr($0, 3); next } !skip[commit] { print }' |
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | awk '!seen[$0]++' > "$FILE"
    if [ ! -s "$FILE" ]; then
        if [ "$CHANNEL" = "release" ]; then
            echo "::warning::No Release-Note-$LANG_CODE trailers since ${BASE:-the beginning} – falling back to commit subjects"
        fi
        git log --reverse --no-merges --format='%s' "$RANGE" | grep -vE '^(Mark|Archive) ' > "$FILE" || true
        touch "$OUT/notes-$LANG_CODE.fallback"
    fi
done
