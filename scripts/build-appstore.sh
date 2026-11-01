#!/bin/bash
# Archives Fernsy for the Mac App Store and exports or uploads it.
#
#   scripts/build-appstore.sh              # → build/appstore/macos/export/Fernsy.pkg
#   PLATFORM=tvos scripts/build-appstore.sh  # the Apple TV app (tvos) or iPhone/iPad app (ios)
#   UPLOAD=1 scripts/build-appstore.sh     # upload straight to App Store Connect
#   VERSION=1.1 scripts/build-appstore.sh  # new version; the build number goes up on every run anyway
#   BUILD_VERSION=1.2 BUILD_NUMBER=214 UPLOAD=1 scripts/build-appstore.sh
#       # version and build number for this build only, the project stays as it is (CI)
#   ASC_KEY=AuthKey.p8 ASC_KEY_ID=… ASC_ISSUER=… scripts/build-appstore.sh
#       # sign through an App Store Connect API key (Admin role) instead of the Xcode account
#
# Needs: the Apple ID of team B8YT7FNB66 in Xcode → Settings → Accounts (signing
# certificates and the App Store provisioning profile are then created automatically),
# and the app record de.mobilistics.fernsy in App Store Connect.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${PLATFORM:-macos}"
case "$PLATFORM" in
    macos) SCHEME=Fernsy; DESTINATION_ARGS=(); FRAMEWORKS=Contents/Frameworks ;;
    tvos) SCHEME="Fernsy TV"; DESTINATION_ARGS=(-destination "generic/platform=tvOS"); FRAMEWORKS=Frameworks ;;
    ios) SCHEME="Fernsy iOS"; DESTINATION_ARGS=(-destination "generic/platform=iOS"); FRAMEWORKS=Frameworks ;;
    *) echo "PLATFORM must be macos, tvos or ios" >&2; exit 2 ;;
esac
OUT="$ROOT/build/appstore/$PLATFORM"
cd "$ROOT"
[ -n "${BUILD_NUMBER:-}" ] || BUMP_BUILD=1 "$ROOT/scripts/set-version.sh"
[ -d "$ROOT/Packages/FernsyPlayer/Frameworks/avcodec.xcframework" ] || "$ROOT/scripts/build-ffmpeg.sh"
rm -rf "$OUT"
mkdir -p "$OUT"

VERSIONS=()
[ -n "${BUILD_VERSION:-}" ] && VERSIONS+=("MARKETING_VERSION=$BUILD_VERSION")
[ -n "${BUILD_NUMBER:-}" ] && VERSIONS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
AUTH=()
if [ -n "${ASC_KEY:-}" ]; then
    : "${ASC_KEY_ID:?ASC_KEY_ID is missing}" "${ASC_ISSUER:?ASC_ISSUER is missing}"
    AUTH=(-authenticationKeyPath "$ASC_KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER")
fi

if [ -n "${ASC_KEY:-}" ] && [ "${CI:-}" = "true" ] && [ "${CERT_CLEANUP:-}" != "workflow" ]; then
    # CI: the archive creates an Apple Development certificate on every fresh runner; revoke it
    # at the end so runs do not fill the team's certificate limit (scripts/ci-dev-certificates.swift).
    swift "$ROOT/scripts/ci-dev-certificates.swift" snapshot "$OUT/dev-certificates.txt"
    trap 'swift "$ROOT/scripts/ci-dev-certificates.swift" revoke-new "$OUT/dev-certificates.txt" || true' EXIT
fi

echo "▸ Archive ($PLATFORM)"
xcodebuild archive -project Fernsy.xcodeproj -scheme "$SCHEME" ${DESTINATION_ARGS[@]+"${DESTINATION_ARGS[@]}"} -configuration Release \
    -archivePath "$OUT/Fernsy.xcarchive" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} ${VERSIONS[@]+"${VERSIONS[@]}"} -quiet

# The archived app must embed the six FFmpeg frameworks and no loose dylib.
APP=$(ls -d "$OUT"/Fernsy.xcarchive/Products/Applications/*.app | head -1)
FW="$APP/$FRAMEWORKS"
for lib in avutil swresample swscale avcodec avformat avfilter; do
    [ -d "$FW/$lib.framework" ] || { echo "✗ $lib.framework missing in the archive" >&2; exit 1; }
done
if ls "$FW"/*.dylib >/dev/null 2>&1; then echo "✗ loose dylibs in the archive: $(ls "$FW"/*.dylib)" >&2; exit 1; fi
echo "✓ FFmpeg frameworks embedded"
if [ "$PLATFORM" = "tvos" ]; then
    [ -d "$APP/PlugIns/FernsyTopShelf.appex" ] || { echo "✗ FernsyTopShelf.appex missing in the archive" >&2; exit 1; }
    echo "✓ Top Shelf extension embedded"
fi

DESTINATION=export
[ "${UPLOAD:-0}" = "1" ] && DESTINATION=upload
sed "s/__DESTINATION__/$DESTINATION/" "$ROOT/Config/ExportOptions-AppStore.plist" > "$OUT/ExportOptions.plist"

echo "▸ Export ($DESTINATION)"
xcodebuild -exportArchive -archivePath "$OUT/Fernsy.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/export" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} -quiet

if [ "$DESTINATION" = "upload" ]; then
    echo "✓ Uploaded – the build appears in App Store Connect → TestFlight after processing"
else
    echo "✓ $(ls "$OUT"/export/*.pkg)"
fi
