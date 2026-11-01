# Fernsy Server

A recorder for one person's IPTV account that runs around the clock in Docker – on a NAS, a home
server or a Raspberry Pi 4 or newer (linux/amd64, linux/arm64). You schedule recordings in the
Fernsy apps as usual; the server records them and puts them into your Fernsy Cloud, where every
Fernsy app plays them. Needs an active Fernsy Cloud subscription.

OpenSpec: `headless-recorder`; decisions in `openspec/changes/*headless-recorder/design.md`.

## Running it

```sh
docker run -d --name fernsy-server --restart unless-stopped \
  -e TZ=Europe/Berlin -p 8080:8080 -v fernsy-data:/data \
  ghcr.io/obi12341/fernsy-server:latest
```

or `docker compose up -d` with [compose.yaml](compose.yaml).

1. Open `http://<host>:8080` (or read `docker logs fernsy-server`): the server shows a code like
   `7K3Q-ABCDEF`, valid 15 minutes, then a new one.
2. In Fernsy on the Mac, iPhone, iPad or Apple TV: Settings › Fernsy Cloud › Server, enter the
   code and choose the IPTV login the server records with.
3. Done: when scheduling a show, choose the server. The status page lists what it records.

When your IPTV password changes (or you move to another account), sign in with the new login on
one of your devices and choose "Use This Login" in the server's settings there. The server checks
it with your provider and only then records with it; a login the provider refuses is reported and
the previous one stays. The settings show which login the server records with.

To remove it, remove the server in the app: it deletes its keys, login and unfinished recordings
and shows a new code. Deleting the volume does the same on the server's side.

## Environment

| Variable | Default | |
|---|---|---|
| `TZ` | UTC | your time zone (for the log and status page; orders carry absolute times) |
| `FERNSY_DATA` | `/data` | the volume |
| `FERNSY_PORT` | `8080` | status page |
| `FERNSY_POLL` | `30` | seconds between two looks for new orders |

## Privacy and what the volume holds

- `secrets.json` (mode 600): your Fernsy Cloud key, the control key the apps share with the
  server, and the IPTV login. Whoever has the volume can record with your login and upload to
  your Fernsy Cloud until you remove the server in the app. Keep the volume private.
- `state.json`: orders and their states. `recordings/`: recordings until they are uploaded
  (deleted then; a recording that cannot be uploaded – storage full, no subscription – is kept for
  7 days).
- Orders and states travel through Fernsy Control encrypted with the control key; that service
  cannot read channels, titles or times. Recordings are encrypted on the server before upload,
  as on the Mac.
- The status page shows the pairing code and what is recorded, without secrets. It has no
  login: keep port 8080 inside your home network and do not forward it to the internet.
- The log names shows and channels, never passwords, keys or stream addresses.

## Development

`swift build` / `swift test` in `server/` (macOS or Linux). Debug builds read `IPTV_CONTROL`,
`IPTV_CLOUD` and `IPTV_CLOUDTOKEN` for the dev services and play the app's part from the command
line (`FernsyServer app-pair <code>`, `app-order <channel> <minutes from now> <minutes>`,
`app-login <user> <password> [server]`, `app-list`, `app-cancel <id>`, `app-remove`; the control key in `FERNSY_DEV_APP`). See
DEVELOPMENT.md › Fernsy Server.

Image: `docker buildx build -f server/Dockerfile --platform linux/amd64,linux/arm64 .` from the
repository root (`--build-arg CONFIGURATION=debug` for tests against the dev services).
