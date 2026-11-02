#!/bin/bash
# App Store media for iPhone, iPad and Apple TV (store-media): screenshots of Fernsy Dev in the
# simulators with the demo server, in German and English, into dist/store/<device>/<language>/.
#
#   scripts/store-media.sh shots                      # build both apps, all devices, de and en
#   scripts/store-media.sh shots --no-build tv en     # only Apple TV, only English
#   scripts/store-media.sh previews                   # app previews (UI test, recorded): iphone ipad tv
#   scripts/store-media.sh previews --no-build ipad de
#   scripts/store-media.sh check                      # every file in both languages, at its size
#
# Devices: iphone (iPhone 18 Pro, 6.3"), duo (iPhone Duo), ipad (iPad Pro 13-inch), tv (Apple TV 4K).
# The scenes are opened by debug switches (DEVELOPMENT.md › iPhone and iPad, Apple TV); the
# simulator takes no input from scripts. WAIT=<s> changes the time each scene gets to load;
# ONLY=<scene prefix> retakes just those scenes (ONLY=03 for the players).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/store"
BUNDLE=de.mobilistics.fernsy.dev
WAIT="${WAIT:-10}"
LANGS="de en"
DEVICES="iphone duo ipad tv"

device_name() {
    case "$1" in
        iphone) echo "iPhone 18 Pro" ;;
        duo) echo "iPhone Duo" ;;
        ipad) echo "iPad Pro 13-inch (M5)" ;;
        tv) echo "Apple TV 4K (3rd generation)" ;;
    esac
}

# Accepted screenshot sizes (App Store Connect, 2 Nov 2026), portrait and landscape.
sizes() {
    case "$1" in
        iphone) echo "1206x2622 2622x1206" ;;
        duo) echo "2007x2853 2853x2007" ;;
        ipad) echo "2064x2752 2752x2064" ;;
        tv) echo "3840x2160" ;;
    esac
}

# The scenes: "<name>|<KEY=value …>"; @SEARCH@ is replaced by a query in the shot's language,
# @CHANNEL@ by a channel showing the middle of the film (good_row).
scenes() {
    case "$1" in
        tv) cat <<'EOF'
01-start|IPTV_TAB=start
02-guide|IPTV_TAB=live IPTV_LIVEVIEW=guide
03-player|IPTV_AUTOPLAY=live:@CHANNEL@ IPTV_PLAYERMODE=info IPTV_KEEPCONTROLS=1
04-film|IPTV_OPEN=fernsy-dev://open?item=movie:500
05-series|IPTV_OPEN=fernsy-dev://open?item=episode:800:00100
06-live|IPTV_TAB=live IPTV_LIVEVIEW=list
07-search|IPTV_TAB=search IPTV_SEARCH=@SEARCH@
08-recordings|IPTV_TAB=recordings IPTV_FRESHRECORDINGS=1 IPTV_MCP=1 IPTV_MCPTOKEN=test
EOF
        ;;
        *) cat <<'EOF'
01-start|IPTV_TAB=start
02-guide|IPTV_TAB=live IPTV_LIVEVIEW=guide
03-player|IPTV_TAB=live IPTV_AUTOPLAY=live:@CHANNEL@ IPTV_PLAYERMODE=channels IPTV_KEEPCONTROLS=1
04-film|IPTV_TAB=films IPTV_DETAIL=movie:500
05-series|IPTV_TAB=series IPTV_DETAIL=series:800
06-live|IPTV_TAB=live IPTV_LIVEVIEW=list
07-search|IPTV_TAB=search IPTV_SEARCH=@SEARCH@
EOF
        ;;
    esac
}

udid() {
    local name="$1"
    xcrun simctl list devices available | grep -F "$name (" | grep -v "at 1080p" | head -1 \
        | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true
}

# Builds of their own (build/store-*): named "Fernsy", not "Fernsy Dev" (the iPad's status bar
# shows the name), without touching the dev builds in build/ios and build/tv.
NAME_SETTING=INFOPLIST_KEY_CFBundleDisplayName=Fernsy

app_path() {
    if [ "$1" = tv ]; then echo "$ROOT/build/store-tv/Build/Products/Debug-appletvsimulator/FernsyTV.app"
    else echo "$ROOT/build/store-ios/Build/Products/Debug-iphonesimulator/FernsyiOS.app"; fi
}

# The app and its UI tests (for the previews) in one build per platform.
build() { build_tests "$1"; }

# A tool of the Apple TV app's debug MCP server (port 52325; the simulator shares the Mac's network).
mcp() {
    curl -s -m 15 http://127.0.0.1:52325/mcp -H "Authorization: Bearer test" -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" </dev/null >/dev/null
}

# Recordings with the shows' real titles: four record the show on now, two of them are stopped
# after a while and so appear as finished.
plan_recordings() {
    sleep "$WAIT"
    for channel in 101 102 103 105; do mcp record "{\"channel_id\":$channel}"; done
    sleep 25
    mcp list_recordings '{}'
    local ids
    ids="$(curl -s -m 15 http://127.0.0.1:52325/mcp -H "Authorization: Bearer test" -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_recordings","arguments":{}}}' </dev/null \
        | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | sort -u | head -2)"
    for id in $ids; do mcp cancel_recording "{\"recording_id\":\"$id\"}"; done
    sleep 5
}

# The iPhone Duo's inner display (2007 × 2853). The simulator starts folded, with the app on the
# cover display (which renders it sideways) and the inner one black; it unfolds only from the
# Simulator's menu, so the shots stop with a hint instead of saving black images.
inner_display() {
    xcrun simctl io "$1" enumerate | awk '/UUID:/ {id=$2} /Default width: 2007/ {print id; exit}'
}

# A black screenshot (folded Duo) compresses to a few kilobytes; a real one has megabytes.
is_black() {
    [ "$(stat -f %z "$1")" -lt 300000 ]
}

# One of the first twelve demo channels that shows the middle of the film for the next minutes, not
# its title cards or credits: the demo server's live loop (659.7 s) is offset by 41 s per channel
# (demo-server/worker.js). Prints its row (0–11).
good_row() {
    python3 -c '
import time
now = time.time()
for row in range(12):
    if 90 < (now + (101 + row) * 41) % 659.712 < 420: print(row); break
else: print(0)'
}

size_of() {
    sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}'
}

shots_for() {
    local device="$1" lang="$2"
    local name dev dir locale search
    name="$(device_name "$device")"
    dev="$(udid "$name")"
    [ -n "$dev" ] || { echo "No '$name' simulator installed." >&2; exit 1; }
    dir="$OUT/$device/$lang"
    mkdir -p "$dir"
    [ -n "${ONLY:-}" ] || rm -f "$dir"/[0-9][0-9]-*.png
    if [ "$lang" = de ]; then locale=de_DE; search=Welt; else locale=en_US; search=World; fi

    xcrun simctl boot "$dev" 2>/dev/null || true
    open -g -a Simulator --args -CurrentDeviceUDID "$dev" 2>/dev/null || true
    xcrun simctl bootstatus "$dev" -b >/dev/null
    if [ "$device" != tv ]; then
        xcrun simctl status_bar "$dev" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
            --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
    fi
    # A fresh install per language: no catalog or guide cached in the other language.
    xcrun simctl terminate "$dev" "$BUNDLE" 2>/dev/null || true
    xcrun simctl uninstall "$dev" "$BUNDLE" 2>/dev/null || true
    xcrun simctl install "$dev" "$(app_path "$device")"
    local display=()
    [ "$device" = duo ] && display=(--display="$(inner_display "$dev")")

    scenes "$device" | while IFS='|' read -r scene switches; do
        case "$scene" in ${ONLY:-}*) ;; *) continue ;; esac
        local envs=(SIMCTL_CHILD_FERNSY_NO_KEYCHAIN=1 SIMCTL_CHILD_IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev
                    SIMCTL_CHILD_IPTV_USER=demo SIMCTL_CHILD_IPTV_PASS=demo)
        local channel=$((101 + $(good_row)))
        for pair in $switches; do
            pair="${pair//@SEARCH@/$search}"
            envs+=("SIMCTL_CHILD_${pair//@CHANNEL@/$channel}")
        done
        # </dev/null: simctl must not read the scene list from the loop's input.
        xcrun simctl terminate "$dev" "$BUNDLE" </dev/null 2>/dev/null || true
        env "${envs[@]}" xcrun simctl launch "$dev" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "$locale" </dev/null >/dev/null
        local wait="$WAIT"
        # The player: past the film's title card.
        case "$scene" in *player*) wait=$((WAIT + 25)) ;; esac
        if [ "$device" = tv ] && [ "$scene" = 08-recordings ]; then plan_recordings; else sleep "$wait"; fi
        xcrun simctl io "$dev" screenshot --type=png "${display[@]+"${display[@]}"}" "$dir/$scene.png" </dev/null >/dev/null 2>&1
        if [ "$device" = duo ] && is_black "$dir/$scene.png"; then
            rm -f "$dir/$scene.png"
            echo "✗ The iPhone Duo simulator is folded: unfold it once in Simulator (Device menu), then run" >&2
            echo "  scripts/store-media.sh shots --no-build duo" >&2
            exit 1
        fi
        echo "  $device/$lang/$scene.png $(size_of "$dir/$scene.png")"
    done
    xcrun simctl terminate "$dev" "$BUNDLE" 2>/dev/null || true
    swift "$ROOT/scripts/store-flatten.swift" "$dir"/[0-9][0-9]-*.png
    [ "$device" = tv ] || xcrun simctl status_bar "$dev" clear
}

# App previews (15–30 s): the size per device; iPhone Duo uses the iPhone's preview.
preview_size() {
    case "$1" in
        iphone) echo "886 1920" ;;
        ipad) echo "1200 1600" ;;
        tv) echo "1920 1080" ;;
    esac
}

build_tests() {
    local devices="$1"
    case " $devices " in *" iphone "*|*" duo "*|*" ipad "*)
        echo "▸ build-for-testing Fernsy iOS"
        taskpolicy -b xcodebuild build-for-testing -project "$ROOT/Fernsy.xcodeproj" -scheme "Fernsy iOS" \
            -destination "platform=iOS Simulator,id=$(udid "iPhone 18 Pro")" -derivedDataPath "$ROOT/build/store-ios" "$NAME_SETTING" -quiet ;;
    esac
    case " $devices " in *" tv "*)
        echo "▸ build-for-testing Fernsy TV"
        taskpolicy -b xcodebuild build-for-testing -project "$ROOT/Fernsy.xcodeproj" -scheme "Fernsy TV" \
            -destination "platform=tvOS Simulator,id=$(udid "Apple TV 4K (3rd generation)")" -derivedDataPath "$ROOT/build/store-tv" "$NAME_SETTING" -quiet ;;
    esac
}

# Records the simulator while StorePreviewUITests walks through the app, then cuts the recording
# at the test's activities "store preview start" and "store preview end".
preview_for() {
    local device="$1" lang="$2"
    local name dev dir work scheme target dd platform recorder started result marks start end seconds
    name="$(device_name "$device")"
    dev="$(udid "$name")"
    [ -n "$dev" ] || { echo "No '$name' simulator installed." >&2; exit 1; }
    dir="$OUT/$device/$lang"; mkdir -p "$dir"
    work="$(mktemp -d)"
    if [ "$device" = tv ]; then
        scheme="Fernsy TV"; target="Fernsy TV UITests"; dd="$ROOT/build/store-tv"; platform="tvOS Simulator"
    else
        scheme="Fernsy iOS"; target="Fernsy iOS UITests"; dd="$ROOT/build/store-ios"; platform="iOS Simulator"
    fi
    xcrun simctl boot "$dev" 2>/dev/null || true
    open -g -a Simulator --args -CurrentDeviceUDID "$dev" 2>/dev/null || true
    xcrun simctl bootstatus "$dev" -b >/dev/null
    [ "$device" = tv ] || xcrun simctl status_bar "$dev" override --time "9:41" --dataNetwork wifi --wifiMode active \
        --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

    # A fresh install: no catalog or guide cached in the other language (the test installs it again).
    xcrun simctl uninstall "$dev" "$BUNDLE" 2>/dev/null || true
    xcrun simctl io "$dev" recordVideo --codec=h264 --force "$work/recording.mov" 2>"$work/record.log" &
    recorder=$!
    for _ in $(seq 1 50); do grep -q "Recording started" "$work/record.log" 2>/dev/null && break; sleep 0.1; done
    started="$(python3 -c 'import time; print(time.time())')"
    result="$work/preview.xcresult"
    TEST_RUNNER_STORE_LANGUAGE="$lang" TEST_RUNNER_STORE_CHANNEL_ROW="$(good_row)" xcodebuild test-without-building -project "$ROOT/Fernsy.xcodeproj" -scheme "$scheme" \
        -destination "platform=$platform,id=$dev" -derivedDataPath "$dd" -quiet -collect-test-diagnostics never \
        -resultBundlePath "$result" "-only-testing:$target/StorePreviewUITests/testPreview" || true
    kill -INT "$recorder"; wait "$recorder" 2>/dev/null || true
    [ "$device" = tv ] || xcrun simctl status_bar "$dev" clear

    # The marks' times (seconds since 1970) from the result bundle.
    marks="$(xcrun xcresulttool get test-results activities --test-id "StorePreviewUITests/testPreview()" --path "$result" 2>/dev/null \
        | python3 -c '
import json, sys
found = {}
def walk(node):
    if isinstance(node, dict):
        if node.get("title") in ("store preview start", "store preview end"): found[node["title"]] = node.get("startTime")
        for value in node.values(): walk(value)
    elif isinstance(node, list):
        for value in node: walk(value)
walk(json.load(sys.stdin))
print(found.get("store preview start", ""), found.get("store preview end", ""))')"
    read -r start end <<<"$marks"
    if [ -z "$start" ] || [ -z "$end" ]; then
        echo "✗ $device/$lang: no marks in the test result (did StorePreviewUITests fail?): $result" >&2
        exit 1
    fi
    read -r start seconds walked <<<"$(python3 -c "s=$start-$started; w=$end-$start; d=min(max(w,15),30); print(round(max(s,0),2), round(d,2), round(w,1))")"
    case "$walked" in
        1[5-9]*|2[0-9]*|30|30.0) ;;
        *) echo "  ! the walk took $walked s, the preview keeps 15–30 s: adjust the pauses in StorePreviewUITests" >&2 ;;
    esac
    read -r w h <<<"$(preview_size "$device")"
    swift "$ROOT/scripts/store-preview.swift" "$work/recording.mov" "$start" "$seconds" "$w" "$h" "$dir/preview.mp4"
    echo "  $device/$lang/preview.mp4 ${w}x${h}, ${seconds} s"
    rm -rf "$work"
}

# Every scene in both languages, at an accepted size, without alpha channel.
check() {
    local devices="${1:-$DEVICES}" ok=1 file size
    for device in $devices; do
        for lang in $LANGS; do
            while IFS='|' read -r scene _; do
                file="$OUT/$device/$lang/$scene.png"
                if [ ! -f "$file" ]; then echo "missing: ${file#"$ROOT"/}"; ok=0; continue; fi
                size="$(size_of "$file")"
                case " $(sizes "$device") " in *" $size "*) ;; *) echo "wrong size $size: ${file#"$ROOT"/}"; ok=0 ;; esac
                if sips -g hasAlpha "$file" | grep -q "hasAlpha: yes"; then echo "has alpha: ${file#"$ROOT"/}"; ok=0; fi
            done < <(scenes "$device")
        done
    done
    [ "$ok" = 1 ] && echo "✓ all screenshots in German and English" || return 1
}

# Everything App Store Connect gets: screenshots, previews, and the iOS header and search images.
check_all() {
    local ok=1 file
    check || ok=0
    for device in iphone ipad tv; do
        for lang in $LANGS; do
            file="$OUT/$device/$lang/preview.mp4"
            [ -f "$file" ] || { echo "missing: ${file#"$ROOT"/}"; ok=0; }
        done
    done
    for lang in $LANGS; do
        for kind in header search; do
            file="$OUT/ios/$lang/$kind.png"
            [ -f "$file" ] || { echo "missing: ${file#"$ROOT"/}"; ok=0; }
        done
    done
    [ "$ok" = 1 ] && echo "✓ all store media in German and English" || return 1
}

command="${1:-}"; shift || true
case "$command" in
    shots)
        BUILD=1
        if [ "${1:-}" = --no-build ]; then BUILD=0; shift; fi
        devices="${1:-all}"; langs="${2:-all}"
        [ "$devices" = all ] && devices="$DEVICES"
        [ "$langs" = all ] && langs="$LANGS"
        [ "$BUILD" = 1 ] && build "$devices"
        for device in $devices; do
            for lang in $langs; do
                echo "▸ $device $lang"
                shots_for "$device" "$lang"
            done
        done
        check "$devices"
        ;;
    previews)
        BUILD=1
        if [ "${1:-}" = --no-build ]; then BUILD=0; shift; fi
        devices="${1:-all}"; langs="${2:-all}"
        [ "$devices" = all ] && devices="iphone ipad tv"
        [ "$langs" = all ] && langs="$LANGS"
        [ "$BUILD" = 1 ] && build_tests "$devices"
        for device in $devices; do
            for lang in $langs; do
                echo "▸ preview $device $lang"
                preview_for "$device" "$lang"
            done
        done
        ;;
    check) check_all ;;
    *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
