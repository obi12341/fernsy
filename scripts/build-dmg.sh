#!/bin/bash
# Builds a Release Fernsy.app and packs it into a DMG (distribution outside the App Store).
# It builds the "Fernsy Direct" target: the app plus the Sparkle updater (the App Store build,
# scripts/build-appstore.sh, uses the "Fernsy" target without it).
# FFmpeg comes from Vendor/ffmpeg (scripts/build-ffmpeg.sh) and is embedded by the build.
#
#   scripts/build-dmg.sh                 # ad-hoc signed (local use, no developer account)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-dmg.sh
#   SIGN_IDENTITY=… NOTARY_PROFILE=fernsy scripts/build-dmg.sh   # + notarize and staple
#   SIGN_IDENTITY=… NOTARY_KEY=AuthKey.p8 NOTARY_KEY_ID=… NOTARY_ISSUER=… scripts/build-dmg.sh
#                                        # + notarize with an App Store Connect API key (CI)
#   VERSION=1.0 scripts/build-dmg.sh     # set a new version (saved in the project, build number +1)
#   BUILD_VERSION=1.2 BUILD_NUMBER=214 scripts/build-dmg.sh   # version for this build only (CI)
#
# NOTARY_PROFILE is a notarytool keychain profile, created once with
#   xcrun notarytool store-credentials fernsy --apple-id … --team-id B8YT7FNB66
# NOTARY_KEY is the path to the API key's .p8 file; NOTARY_KEY_ID and NOTARY_ISSUER are its
# key ID and issuer ID from App Store Connect (Users and Access › Integrations).
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
    # Notarization requires the hardened runtime and rejects the get-task-allow (debugging)
    # entitlement Xcode injects by default; set both here instead of relying on the project.
    SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" ENABLE_HARDENED_RUNTIME=YES
             CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp)
fi

# CI passes the version from the tag and the build number from git, without editing the project.
[ -n "${BUILD_VERSION:-}" ] && SIGNING+=("MARKETING_VERSION=$BUILD_VERSION")
[ -n "${BUILD_NUMBER:-}" ] && SIGNING+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

echo "▸ Release build ($([ "$SIGN_IDENTITY" = "-" ] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
xcodebuild -project Fernsy.xcodeproj -scheme "Fernsy Direct" -configuration Release \
    -derivedDataPath "$BUILD/DerivedData" "${SIGNING[@]}" build -quiet 2>&1 \
    | grep -v "DVTPlugIn\|IDESimulatorFoundation\|CoreSimulator\|^\s*Referenced from\|^\s*Reason:" || true
APP="$BUILD/DerivedData/Build/Products/Release/Fernsy.app"
[ -x "$APP/Contents/MacOS/Fernsy" ] || { echo "Build failed"; exit 1; }
codesign --verify --deep --strict "$APP"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$SPARKLE/Versions/B/XPCServices/Installer.xpc" ] || { echo "Sparkle or its installer service is missing"; exit 1; }
if [ "$SIGN_IDENTITY" != "-" ]; then
    # Xcode signs Sparkle.framework but leaves its helpers ad-hoc signed, which notarization
    # rejects. Re-sign them inside out (Sparkle's documented order), then the app again with
    # the entitlements it was built with.
    echo "▸ Signing Sparkle's helpers"
    SIGN=(codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
    "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
    "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
    "${SIGN[@]}" "$SPARKLE"
    codesign -d --entitlements - --xml "$APP" > "$BUILD/app.entitlements" 2>/dev/null
    "${SIGN[@]}" --entitlements "$BUILD/app.entitlements" "$APP"
fi
codesign --verify --deep --strict "$SPARKLE"
codesign --verify --deep --strict "$APP"
# Read codesign's output first: with pipefail, grep -q can end the pipe early and codesign's
# SIGPIPE fails the check at random.
SIGNATURE=$(codesign -dv "$APP" 2>&1)
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null)
if [ "$SIGN_IDENTITY" != "-" ] && ! grep -q "flags=.*runtime" <<< "$SIGNATURE"; then
    echo "The app is not signed with the hardened runtime"; exit 1
fi
if [ "$SIGN_IDENTITY" != "-" ] && grep -q "get-task-allow" <<< "$ENTITLEMENTS"; then
    echo "The app still requests com.apple.security.get-task-allow"; exit 1
fi
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "▸ Smoke test (libraries load from the bundle only)"
# The loaded libraries come from lsof: dyld ignores DYLD_PRINT_LIBRARIES in a signed build
# (hardened runtime without get-task-allow) on a Mac with SIP on.
FERNSY_NO_KEYCHAIN=1 "$APP/Contents/MacOS/Fernsy" > /dev/null 2>&1 &
PID=$!
sleep 3
lsof -p "$PID" -Fn 2>/dev/null | sed -n 's/^n//p' > "$BUILD/launch.log" || true
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
    if [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${NOTARY_KEY:-}" ]; then
        echo "▸ Notarizing"
        if [ -n "${NOTARY_KEY:-}" ]; then
            : "${NOTARY_KEY_ID:?NOTARY_KEY_ID is missing}" "${NOTARY_ISSUER:?NOTARY_ISSUER is missing}"
            NOTARY=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
        else
            NOTARY=(--keychain-profile "$NOTARY_PROFILE")
        fi
        xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait | tee "$BUILD/notary.txt"
        if ! grep -q "status: Accepted" "$BUILD/notary.txt"; then
            # notarytool exits 0 for an "Invalid" result; show Apple's reasons and stop.
            SUBMISSION=$(grep -m1 -o 'id: [0-9a-f-]*' "$BUILD/notary.txt" | cut -d' ' -f2)
            [ -n "$SUBMISSION" ] && xcrun notarytool log "$SUBMISSION" "${NOTARY[@]}" || true
            echo "Notarization failed"; exit 1
        fi
        xcrun stapler staple "$DMG"
    fi
fi

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
