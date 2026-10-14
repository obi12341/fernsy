#!/bin/bash
# VERSION=x.y → MARKETING_VERSION = x.y and CURRENT_PROJECT_VERSION + 1 in the project.
# BUMP_BUILD=1 → CURRENT_PROJECT_VERSION + 1 only (App Store Connect needs a new build
# number for every upload). Without either nothing changes.
set -euo pipefail
[ -n "${VERSION:-}" ] || [ "${BUMP_BUILD:-0}" = "1" ] || exit 0
PBXPROJ="$(cd "$(dirname "$0")/.." && pwd)/Fernsy.xcodeproj/project.pbxproj"
BUILD_NUMBER=$(( $(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$PBXPROJ" | grep -o '[0-9]*$') + 1 ))
sed -i '' -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" "$PBXPROJ"
[ -n "${VERSION:-}" ] && sed -i '' -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/" "$PBXPROJ"
echo "▸ Version $(grep -m1 -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | cut -d' ' -f3) (Build $BUILD_NUMBER)"
