#!/bin/bash
# Renders the iOS app's product page header (3840 × 1646) and search results image
# (3840 × 2560) in German and English from art.html with headless Chrome, using the screenshots
# of `scripts/store-media.sh shots` (store-media). The lines of text are those of
# docs/app-store.md › "Kopfzeile und Suchergebnisse"; keep both in step.
#
#   scripts/store-art/render.sh            # into dist/store/ios/<language>/header.png, search.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/dist/store"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

line() {
    case "$1-$2" in
        header-de) echo "Dein Fernsehen. Auf jedem Bildschirm." ;;
        header-en) echo "Your TV. On every screen." ;;
        search-de) echo "Live-TV, Programm und Filme in einer App" ;;
        search-en) echo "Live TV, guide and movies in one app" ;;
    esac
}

for lang in de en; do
    for shot in iphone/$lang/01-start.png iphone/$lang/04-film.png ipad/$lang/02-guide.png; do
        [ -f "$OUT/$shot" ] || { echo "missing dist/store/$shot: run scripts/store-media.sh shots first" >&2; exit 1; }
    done
    mkdir -p "$OUT/ios/$lang"
    for kind in header search; do
        if [ "$kind" = header ]; then w=3840; h=1646; else w=3840; h=2560; fi
        page="$WORK/$kind-$lang.html"
        sed -e "s|{{W}}|$w|g" -e "s|{{H}}|$h|g" -e "s|{{KIND}}|$kind|g" -e "s|{{LANG}}|$lang|g" \
            -e "s|{{SHOTS}}|file://$OUT|g" -e "s|{{ICON}}|file://$ROOT/website/assets/icon.png|g" \
            -e "s|{{LINE}}|$(line "$kind" "$lang")|g" "$ROOT/scripts/store-art/art.html" > "$page"
        "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
            --allow-file-access-from-files --window-size="$w,$h" --virtual-time-budget=3000 \
            --screenshot="$OUT/ios/$lang/$kind.png" "file://$page" >/dev/null 2>&1
        swift "$ROOT/scripts/store-flatten.swift" "$OUT/ios/$lang/$kind.png"
        size="$(sips -g pixelWidth -g pixelHeight "$OUT/ios/$lang/$kind.png" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"
        [ "$size" = "${w}x${h}" ] || { echo "dist/store/ios/$lang/$kind.png is $size, not ${w}x${h}" >&2; exit 1; }
        echo "  ios/$lang/$kind.png $size"
    done
done
