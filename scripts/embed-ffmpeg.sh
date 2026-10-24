#!/bin/sh
# Xcode build phase: copies the FFmpeg libraries from Vendor/ffmpeg (scripts/build-ffmpeg.sh)
# into Fernsy.app/Contents/Frameworks under their install names and signs them with the
# app's identity, so archive/export and the Mac App Store see a self-contained bundle.
set -eu

LIB="$FFMPEG_PREFIX/lib"
DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
if [ ! -d "$LIB" ]; then
    echo "error: $LIB missing – run scripts/build-ffmpeg.sh first"
    exit 1
fi
mkdir -p "$DEST"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[ -n "$IDENTITY" ] || IDENTITY="-"
# A secure timestamp when the app itself is signed with one (scripts/build-dmg.sh passes
# --timestamp for Developer ID builds; notarization rejects binaries without it). Other builds
# skip it, so they do not need the timestamp server.
case " ${OTHER_CODE_SIGN_FLAGS:-} " in
    *" --timestamp "*) TIMESTAMP=--timestamp ;;
    *) TIMESTAMP=--timestamp=none ;;
esac

for lib in "$LIB"/lib*.dylib; do
    name=$(basename "$lib")
    # Only lib<name>.<major>.dylib – the names the binaries reference (@rpath/…).
    echo "$name" | grep -Eq '^lib[a-z0-9_]+\.[0-9]+\.dylib$' || continue
    cp -fL "$lib" "$DEST/$name"
    chmod 644 "$DEST/$name"
    codesign --force --sign "$IDENTITY" "$TIMESTAMP" "$DEST/$name"
done
