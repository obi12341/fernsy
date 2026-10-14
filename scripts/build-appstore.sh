#!/bin/bash
# Archives Fernsy for the Mac App Store and exports or uploads it.
#
#   scripts/build-appstore.sh              # → build/appstore/export/Fernsy.pkg
#   UPLOAD=1 scripts/build-appstore.sh     # upload straight to App Store Connect
#   VERSION=1.1 scripts/build-appstore.sh  # new version; the build number goes up on every run anyway
#
# Needs: the Apple ID of team B8YT7FNB66 in Xcode → Settings → Accounts (signing
# certificates and the App Store provisioning profile are then created automatically),
# and the app record de.mobilistics.fernsy in App Store Connect.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/appstore"
cd "$ROOT"
BUMP_BUILD=1 "$ROOT/scripts/set-version.sh"
[ -d "$ROOT/Vendor/ffmpeg/lib" ] || "$ROOT/scripts/build-ffmpeg.sh"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Archive"
xcodebuild archive -project Fernsy.xcodeproj -scheme Fernsy -configuration Release \
    -archivePath "$OUT/Fernsy.xcarchive" -allowProvisioningUpdates -quiet

DESTINATION=export
[ "${UPLOAD:-0}" = "1" ] && DESTINATION=upload
sed "s/__DESTINATION__/$DESTINATION/" "$ROOT/Config/ExportOptions-AppStore.plist" > "$OUT/ExportOptions.plist"

echo "▸ Export ($DESTINATION)"
xcodebuild -exportArchive -archivePath "$OUT/Fernsy.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/export" -allowProvisioningUpdates -quiet

if [ "$DESTINATION" = "upload" ]; then
    echo "✓ Uploaded – the build appears in App Store Connect → TestFlight after processing"
else
    echo "✓ $(ls "$OUT"/export/*.pkg)"
fi
