#!/bin/bash
# jellyfin-test-server.sh: a throwaway Jellyfin for tests on 127.0.0.1:8097 (container fernsy-jf-fixtures, user
# fixture / fixture-pass) with an 8-minute film and a series of three 2-minute episodes.
# --surround adds a library "Surround" with three one-minute films (AC-3 5.1, E-AC-3 5.1,
# FLAC 7.1); the UI tests expect the library without it.
# Remove it afterwards: docker rm -f fernsy-jf-fixtures
set -euo pipefail
SURROUND=0
[ "${1:-}" = --surround ] && SURROUND=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="$ROOT/build/jellyfin-test"   # generated clips (git-ignored)
IMG=jellyfin/jellyfin
clip() { # out, seconds, title
    [ -f "$M/$1" ] && return
    mkdir -p "$(dirname "$M/$1")"
    docker run --rm -v "$M:/media" --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg $IMG -loglevel error \
        -f lavfi -i "testsrc2=size=1280x720:rate=25" -f lavfi -i "sine=frequency=440" -t "$2" \
        -vf "drawtext=text='$3 %{pts\:hms}':fontsize=48:fontcolor=white:x=40:y=40" \
        -c:v libx264 -preset veryfast -c:a aac -metadata:s:a:0 language=eng "/media/$1"
}
clip "movies/Fixture Film (2024)/Fixture Film (2024).mkv" 480 "Fixture Film"
# Surround clips (apple-tv-surround): one tone per channel, each its own frequency, so channel
# order and passthrough can be checked. Test content only; the app's FFmpeg stays LGPL without
# encoders.
surround() { # out, codec, layout, channels, extra encoder args…
    local out="$1" codec="$2" layout="$3" n="$4"; shift 4
    [ -f "$M/$out" ] && return
    mkdir -p "$(dirname "$M/$out")"
    # One tone per channel in the layout's order. The map is explicit: join would put every mono
    # sine (front centre) on FC first.
    local freqs=(300 400 500 60 600 700 800 900) names=(FL FR FC LFE BL BR SL SR) graph="" inputs="" map=""
    [ "$layout" = "5.1(side)" ] && names=(FL FR FC LFE SL SR)
    for i in $(seq 0 $((n - 1))); do
        graph+="sine=frequency=${freqs[$i]}:duration=60[a$i];"; inputs+="[a$i]"; map+="${map:+|}$i.0-${names[$i]}"
    done
    docker run --rm -v "$M:/media" --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg $IMG -loglevel error \
        -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=60" \
        -filter_complex "${graph}${inputs}join=inputs=$n:channel_layout=$layout:map=$map[a]" \
        -vf "drawtext=text='$codec $layout %{pts\:hms}':fontsize=48:fontcolor=white:x=40:y=40" \
        -map 0:v -map "[a]" -c:v libx264 -preset veryfast -c:a "$codec" "$@" -metadata:s:a:0 language=eng "/media/$out"
}
# Always generated (SurroundAudioTests reads them), in the library only with --surround.
surround "surround/Surround AC3 (2024)/Surround AC3 (2024).mkv" ac3 "5.1(side)" 6 -b:a 448k
surround "surround/Surround EAC3 (2024)/Surround EAC3 (2024).mkv" eac3 "5.1(side)" 6 -b:a 640k
# FFmpeg's AC-3/E-AC-3/TrueHD encoders stop at 5.1: 7.1 (decoded by Fernsy itself) comes as FLAC.
surround "surround/Surround FLAC 7.1 (2024)/Surround FLAC 7.1 (2024).mkv" flac 7.1 8
for e in 1 2 3; do clip "shows/Fixture Show/Season 01/Fixture Show S01E0$e.mkv" 120 "S01E0$e"; done

docker rm -f fernsy-jf-fixtures >/dev/null 2>&1 || true
docker run -d --name fernsy-jf-fixtures -p 127.0.0.1:8097:8096 -v "$M:/media:ro" $IMG >/dev/null
J=http://127.0.0.1:8097
until curl -sf $J/System/Info/Public >/dev/null; do sleep 2; done
H='Content-Type: application/json'
# The startup wizard answers a while after /System/Info/Public; with set -e a first early call
# ended the script silently and left the wizard open.
until curl -sf -X POST $J/Startup/Configuration -H "$H" -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null; do sleep 2; done
curl -sf $J/Startup/User >/dev/null
curl -sf -X POST $J/Startup/User -H "$H" -d '{"Name":"fixture","Password":"fixture-pass"}' >/dev/null
curl -sf -X POST $J/Startup/RemoteAccess -H "$H" -d '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/dev/null
curl -sf -X POST $J/Startup/Complete >/dev/null
AUTH='MediaBrowser Client="setup", Device="setup", DeviceId="fernsy-setup", Version="1"'
TOKEN=$(curl -sf -X POST $J/Users/AuthenticateByName -H "$H" -H "Authorization: $AUTH" -d '{"Username":"fixture","Pw":"fixture-pass"}' | python3 -c "import json,sys;print(json.load(sys.stdin)['AccessToken'])")
A="Authorization: $AUTH, Token=\"$TOKEN\""
curl -sf -X POST "$J/Library/VirtualFolders?name=Films&collectionType=movies&paths=/media/movies&refreshLibrary=false" -H "$A" -H "$H" -d '{"LibraryOptions":{"EnableRealtimeMonitor":false,"MetadataSavers":[],"TypeOptions":[]}}' >/dev/null
curl -sf -X POST "$J/Library/VirtualFolders?name=Series&collectionType=tvshows&paths=/media/shows&refreshLibrary=false" -H "$A" -H "$H" -d '{"LibraryOptions":{"EnableRealtimeMonitor":false,"MetadataSavers":[],"TypeOptions":[]}}' >/dev/null
if [ "$SURROUND" = 1 ]; then
    # No internet metadata: Jellyfin took "Surround AC3 (2024)" for a real film.
    curl -sf -X POST "$J/Library/VirtualFolders?name=Surround&collectionType=movies&paths=/media/surround&refreshLibrary=false" -H "$A" -H "$H" \
        -d '{"LibraryOptions":{"EnableRealtimeMonitor":false,"MetadataSavers":[],"TypeOptions":[{"Type":"Movie","MetadataFetchers":[],"ImageFetchers":[]}]}}' >/dev/null
fi
curl -sf -X POST "$J/Library/Refresh" -H "$A" >/dev/null
for i in $(seq 1 60); do
    n=$(curl -sf "$J/Items?recursive=true&includeItemTypes=Movie,Episode" -H "$A" | python3 -c "import json,sys;print(json.load(sys.stdin)['TotalRecordCount'])")
    [ "$n" -ge 4 ] && break; sleep 2
done
# The state the detail page tests expect (DetailPagesUITests): the film resumes at 2:30 and
# S01E01-02 are watched, so S01E03 is next.
UID_=$(curl -sf "$J/Users/Me" -H "$A" | python3 -c "import json,sys;print(json.load(sys.stdin)['Id'])")
item() { curl -sf "$J/Items?userId=$UID_&recursive=true&includeItemTypes=$1&searchTerm=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$2")" -H "$A" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['Items'][0]['Id'])"; }
curl -sf -X POST "$J/UserItems/$(item Movie 'Fixture Film')/UserData?userId=$UID_" -H "$A" -H "$H" -d '{"PlaybackPositionTicks":1500000000}' >/dev/null
for e in 1 2; do curl -sf -X POST "$J/UserPlayedItems/$(item Episode "S01E0$e")?userId=$UID_" -H "$A" >/dev/null; done
echo "Jellyfin on $J: $n items (fixture / fixture-pass)"
