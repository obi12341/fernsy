#!/bin/bash
# Builds the FFmpeg libraries Fernsy links against: LGPL only (no --enable-gpl, no
# nonfree), decoding only (no encoders, muxers, network, devices, programs), arm64,
# shared libraries with @rpath install names so they can be embedded in the app.
#
#   scripts/build-ffmpeg.sh            # → Vendor/ffmpeg/{include,lib}
#   FFMPEG_VERSION=9.0.2 scripts/build-ffmpeg.sh
#
# The source tarball is kept in build/ffmpeg; its URL and the configure line are printed
# into Vendor/ffmpeg/BUILDINFO.txt (needed for the LGPL source offer).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FFMPEG_VERSION:-9.0.2}"
URL="https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
WORK="$ROOT/build/ffmpeg"
PREFIX="$ROOT/Vendor/ffmpeg"
MIN_MACOS=14.0

mkdir -p "$WORK"
cd "$WORK"
[ -f "ffmpeg-$VERSION.tar.xz" ] || curl -fL -o "ffmpeg-$VERSION.tar.xz" "$URL"
rm -rf "ffmpeg-$VERSION"
tar xf "ffmpeg-$VERSION.tar.xz"
cd "ffmpeg-$VERSION"

CONFIGURE=(
    --prefix="$PREFIX"
    --arch=arm64 --target-os=darwin --cc=clang
    --extra-cflags="-mmacosx-version-min=$MIN_MACOS" --extra-ldflags="-mmacosx-version-min=$MIN_MACOS"
    --enable-shared --disable-static --install-name-dir=@rpath
    --disable-gpl --disable-nonfree
    --disable-programs --disable-doc --disable-avdevice --disable-network
    --disable-encoders --disable-muxers --disable-devices --disable-protocols --disable-indevs --disable-outdevs
    --disable-autodetect --enable-videotoolbox --enable-metal --enable-zlib
    --disable-debug
)
./configure "${CONFIGURE[@]}"
make -j"$(sysctl -n hw.ncpu)"
rm -rf "$PREFIX"
make install

# Keep only what linking and embedding need.
rm -rf "$PREFIX/share" "$PREFIX/lib/pkgconfig"
{
    echo "FFmpeg $VERSION ($URL)"
    echo "License: LGPL-2.1-or-later"
    echo "configure ${CONFIGURE[*]}"
} > "$PREFIX/BUILDINFO.txt"
cp COPYING.LGPLv2.1 "$PREFIX/COPYING.LGPLv2.1"

if grep -q "CONFIG_GPL 1\|CONFIG_NONFREE 1" "$PREFIX/include/libavutil/avconfig.h" config.h 2>/dev/null; then
    echo "GPL/nonfree components enabled – refusing"; exit 1
fi
echo "✓ FFmpeg $VERSION in $PREFIX ($(du -sh "$PREFIX/lib" | cut -f1))"
