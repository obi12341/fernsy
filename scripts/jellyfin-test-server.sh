#!/bin/bash
# jellyfin-test-server.sh: a throwaway Jellyfin for tests on 127.0.0.1:8097 (container fernsy-jf-fixtures, user
# fixture / fixture-pass) with an 8-minute film and a series of three 2-minute episodes.
# Remove it afterwards: docker rm -f fernsy-jf-fixtures
set -euo pipefail
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
