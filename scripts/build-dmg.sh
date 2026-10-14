#!/bin/bash
# Builds a Release Fernsy.app and packs it into a DMG (distribution outside the App Store).
# FFmpeg comes from Vendor/ffmpeg (scripts/build-ffmpeg.sh) and is embedded by the build.
#
#   scripts/build-dmg.sh                 # ad-hoc signed (local use, no developer account)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-dmg.sh
#   SIGN_IDENTITY=… NOTARY_PROFILE=fernsy scripts/build-dmg.sh   # + notarize and staple
#   VERSION=1.0 scripts/build-dmg.sh     # set a new version (saved in the project, build number +1)
#
# NOTARY_PROFILE is a notarytool keychain profile, created once with
#   xcrun notarytool store-credentials fernsy --apple-id … --team-id B8YT7FNB66
#
# Output: dist/Fernsy-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT"
"$ROOT/scripts/set-version.sh"
[ -d "$ROOT/Vendor/ffmpeg/lib" ] || "$ROOT/scripts/build-ffmpeg.sh"
rm -rf "$BUILD"
mkdir -p "$DIST"

if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
else
    SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" OTHER_CODE_SIGN_FLAGS=--timestamp)
fi

echo "▸ Release build ($([ "$SIGN_IDENTITY" = "-" ] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
xcodebuild -project Fernsy.xcodeproj -scheme Fernsy -configuration Release \
    -derivedDataPath "$BUILD/DerivedData" "${SIGNING[@]}" build -quiet 2>&1 \
    | grep -v "DVTPlugIn\|IDESimulatorFoundation\|CoreSimulator\|^\s*Referenced from\|^\s*Reason:" || true
APP="$BUILD/DerivedData/Build/Products/Release/Fernsy.app"
[ -x "$APP/Contents/MacOS/Fernsy" ] || { echo "Build failed"; exit 1; }
codesign --verify --deep --strict "$APP"
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "▸ Smoke test (libraries load from the bundle only)"
FERNSY_NO_KEYCHAIN=1 DYLD_PRINT_LIBRARIES=1 "$APP/Contents/MacOS/Fernsy" > "$BUILD/launch.log" 2>&1 &
PID=$!
sleep 3
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
if grep -q "/opt/homebrew\|/usr/local\|Vendor/ffmpeg" "$BUILD/launch.log"; then
    echo "App loads libraries from outside the bundle:"; grep "/opt/homebrew\|/usr/local\|Vendor/ffmpeg" "$BUILD/launch.log" | head; exit 1
fi
grep -q "Frameworks/libavcodec" "$BUILD/launch.log" || { echo "libavcodec not loaded from bundle"; tail -20 "$BUILD/launch.log"; exit 1; }

echo "▸ Creating DMG"
DMG_ROOT="$BUILD/dmg"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Programme"
DMG="$DIST/Fernsy-$APP_VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Fernsy" -srcfolder "$DMG_ROOT" -fs APFS -format ULMO -ov "$DMG" -quiet

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "▸ Notarizing"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
