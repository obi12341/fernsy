#!/bin/bash
# Builds the FFmpeg libraries Fernsy links against: LGPL only (no --enable-gpl, no
# nonfree), decoding plus the MPEG-TS muxer for timeshift and recordings (no encoders,
# network, devices, programs), arm64, as dynamic frameworks (LGPL: replaceable) for
# macOS, tvOS and the tvOS simulator, combined into one XCFramework per library.
#
#   scripts/build-ffmpeg.sh                  # all platforms
#   PLATFORMS=macos scripts/build-ffmpeg.sh  # only some (macos, tvos, tvsim)
#   FFMPEG_VERSION=9.0.2 scripts/build-ffmpeg.sh
#
# Output (git-ignored), used by Packages/FernsyPlayer:
#   Packages/FernsyPlayer/Frameworks/<lib>.xcframework   binaries, one slice per platform
#   Packages/FernsyPlayer/Sources/CFFShim/include/lib*   headers for the C bridge
#   Packages/FernsyPlayer/Frameworks/BUILDINFO.txt       source URL and configure lines (LGPL
#                                                      source offer), plus COPYING.LGPLv2.1
# The source tarball and the per-platform builds are kept in build/ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FFMPEG_VERSION:-9.0.2}"
URL="https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
WORK="$ROOT/build/ffmpeg"
OUT="$ROOT/Packages/FernsyPlayer/Frameworks"
HEADERS="$ROOT/Packages/FernsyPlayer/Sources/CFFShim/include"
PLATFORMS="${PLATFORMS:-macos tvos tvsim}"
MIN_MACOS=14.0
MIN_TVOS=27.0
# In dependency order: each library only links the ones before it.
LIBS=(avutil swresample swscale avcodec avformat avfilter)

mkdir -p "$WORK"
cd "$WORK"
[ -f "ffmpeg-$VERSION.tar.xz" ] || curl -fL -o "ffmpeg-$VERSION.tar.xz" "$URL"
rm -rf "ffmpeg-$VERSION"
tar xf "ffmpeg-$VERSION.tar.xz"
SRC="$WORK/ffmpeg-$VERSION"

COMMON=(
    --enable-shared --disable-static --install-name-dir=@rpath
    --disable-gpl --disable-nonfree
    --disable-programs --disable-doc --disable-avdevice --disable-network
    --disable-encoders --disable-muxers --enable-muxer=mpegts --disable-devices --disable-protocols --disable-indevs --disable-outdevs
    --disable-autodetect --enable-videotoolbox --enable-zlib
    --disable-debug
)

# platform → configure flags, framework layout and Info.plist values
platform_flags() {
    case "$1" in
    macos)
        echo "--arch=arm64 --target-os=darwin --cc=clang --enable-metal"
        echo "--extra-cflags=-mmacosx-version-min=$MIN_MACOS --extra-ldflags=-mmacosx-version-min=$MIN_MACOS" ;;
    tvos)
        local sdk; sdk="$(xcrun --sdk appletvos --show-sdk-path)"
        echo "--arch=arm64 --target-os=darwin --enable-cross-compile --cc=$(xcrun --sdk appletvos -f clang) --sysroot=$sdk"
        echo "--extra-cflags=-target --extra-cflags=arm64-apple-tvos$MIN_TVOS --extra-ldflags=-target --extra-ldflags=arm64-apple-tvos$MIN_TVOS" ;;
    tvsim)
        local sdk; sdk="$(xcrun --sdk appletvsimulator --show-sdk-path)"
        echo "--arch=arm64 --target-os=darwin --enable-cross-compile --cc=$(xcrun --sdk appletvsimulator -f clang) --sysroot=$sdk"
        echo "--extra-cflags=-target --extra-cflags=arm64-apple-tvos$MIN_TVOS-simulator --extra-ldflags=-target --extra-ldflags=arm64-apple-tvos$MIN_TVOS-simulator" ;;
    esac
}

# Writes <lib>.framework for one platform from the installed dylibs.
make_framework() {
    local platform="$1" lib="$2" prefix="$3" dest="$4"
    local real; real="$(cd "$prefix/lib" && readlink -f "lib$lib.dylib")"
    local fw="$dest/$lib.framework" binary plist supported minkey minvalue
    rm -rf "$fw"
    case "$platform" in
    macos)
        # macOS frameworks are versioned bundles (codesign refuses shallow ones there).
        mkdir -p "$fw/Versions/A/Resources"
        binary="$fw/Versions/A/$lib"; plist="$fw/Versions/A/Resources/Info.plist"
        ln -s A "$fw/Versions/Current"
        ln -s "Versions/Current/$lib" "$fw/$lib"
        ln -s Versions/Current/Resources "$fw/Resources"
        supported=MacOSX; minkey=LSMinimumSystemVersion; minvalue=$MIN_MACOS ;;
    tvos|tvsim)
        mkdir -p "$fw"
        binary="$fw/$lib"; plist="$fw/Info.plist"
        supported=$([ "$platform" = tvos ] && echo AppleTVOS || echo AppleTVSimulator)
        minkey=MinimumOSVersion; minvalue=$MIN_TVOS ;;
    esac
    cp "$real" "$binary"
    install_name_tool -id "@rpath/$lib.framework/$lib" "$binary"
    # Links to the other libraries move from @rpath/libX.N.dylib to the frameworks.
    otool -L "$binary" | awk '/@rpath\/lib/ {print $1}' | while read -r dep; do
        local name; name="$(basename "$dep" | sed -E 's/^lib([a-z]+)\..*/\1/')"
        install_name_tool -change "$dep" "@rpath/$name.framework/$name" "$binary"
    done
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>$lib</string>
<key>CFBundleIdentifier</key><string>org.ffmpeg.$lib</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>$lib</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleSupportedPlatforms</key><array><string>$supported</string></array>
<key>$minkey</key><string>$minvalue</string>
</dict></plist>
EOF
}

BUILDINFO=("FFmpeg $VERSION ($URL)" "License: LGPL-2.1-or-later")
for platform in $PLATFORMS; do
    dir="$WORK/$platform"; prefix="$dir/prefix"
    rm -rf "$dir"; mkdir -p "$dir"
    # shellcheck disable=SC2207
    flags=($(platform_flags "$platform"))
    (
        cd "$dir"
        "$SRC/configure" --prefix="$prefix" "${flags[@]}" "${COMMON[@]}"
        if grep -q "CONFIG_GPL 1\|CONFIG_NONFREE 1" config.h; then
            echo "GPL/nonfree components enabled for $platform – refusing"; exit 1
        fi
        make -j"$(sysctl -n hw.ncpu)"
        make install
    )
    mkdir -p "$dir/frameworks"
    for lib in "${LIBS[@]}"; do make_framework "$platform" "$lib" "$prefix" "$dir/frameworks"; done
    BUILDINFO+=("configure ($platform) ${flags[*]} ${COMMON[*]}")
done

# One XCFramework per library from the platforms built now (all of them for a release).
rm -rf "$OUT"; mkdir -p "$OUT"
for lib in "${LIBS[@]}"; do
    args=()
    for platform in $PLATFORMS; do args+=(-framework "$WORK/$platform/frameworks/$lib.framework"); done
    xcodebuild -create-xcframework "${args[@]}" -output "$OUT/$lib.xcframework" >/dev/null
done
first="$(echo "$PLATFORMS" | awk '{print $1}')"
rm -rf "$HEADERS"/lib*
mkdir -p "$HEADERS"
cp -R "$WORK/$first/prefix/include/"lib* "$HEADERS/"
printf '%s\n' "${BUILDINFO[@]}" > "$OUT/BUILDINFO.txt"
cp "$SRC/COPYING.LGPLv2.1" "$OUT/COPYING.LGPLv2.1"
echo "✓ FFmpeg $VERSION for $PLATFORMS in $OUT ($(du -sh "$OUT" | cut -f1))"
