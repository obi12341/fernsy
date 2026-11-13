# Tasks

## 1. Detection

- [x] 1.1 Add `VPNProbe` to `FernsyCore` (design 2): the rule over injected per-family lookups (tunnel names, "every family with a route", "at least one route") and the real lookup (connected UDP socket, `getsockname`, `getifaddrs`). Verify with unit tests for: full tunnel on both families, IPv4 tunnelled with IPv6 direct, IPv4 only tunnelled without IPv6 route, split tunnel present but unused, no route at all (`scripts/vm.sh scripts/test.sh`).
- [x] 1.2 Check the real lookup where it will run, before building on it: on the development Mac (Tailscale as split tunnel: expect "no VPN, en0"), in the Tart VM with a `utun` that holds full-tunnel routes (`0.0.0.0/1`, `128.0.0.0/1`; expect "VPN, utunN") and after removing them, and inside the tvOS and iOS simulators. Record the results under "Notes from implementing" in design.md; if the lookup is unusable on a platform, switch that platform to the `NWPath` fallback named in the design's risks and update decision 2.
- [x] 1.3 Add the debug switch `IPTV_TESTVPN=on|off` that replaces the probe's answer, and document it in DEVELOPMENT.md next to `IPTV_TESTOFFLINE`. Verify with a unit test that the faked answer wins over the lookup.

## 2. Gate and setting

- [x] 2.1 Add `ProviderGate` and `ProviderGateError.vpnRequired` to `FernsyShared` (design 3): setting in `UserDefaults` (not in `ICloudSync.syncedKeys`), `check()`, `isOpen`, change notification driven by the models' `NWPathMonitor`, always open on Linux, a log line per change and per refusal with the interface names. Add `IPTV_TESTVPNGUARD=1` (setting on for this run) and document it in DEVELOPMENT.md. Verify with unit tests: setting off → open whatever the probe says; on + no VPN → `check()` throws; on + VPN → open; and that `swift build` in `server/` still succeeds.
- [x] 2.2 Add the error's message to the package's string catalog in English and German ("No VPN connection. Fernsy contacts your IPTV provider only through a VPN." and its German text) and make `ProviderGateError` count as a connection failure where the apps classify errors (`TVModel.isConnectionFailure` and the Mac's handling). Verify with a unit test for the classification and that the catalog has both languages.
- [x] 2.3 Check the gate in `XtreamClient`'s request function. Verify with the client's existing protocol-backed tests: with `IPTV_TESTVPN=off` and the guard on, a catalog call throws `vpnRequired` and the recording protocol saw no request; with `IPTV_TESTVPN=on` it answers.

## 3. Streams

- [x] 3.1 Give `HTTPByteSource` the provider flag and pass it from `PlaybackSession` (`.network`, `.tuner`) and the MCP frame source: true for Xtream URLs, false for Jellyfin. A first connection with the gate closed fails with `ProviderGateError.vpnRequired` and is not retried by the session. Verify on the host against the demo server: `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=off`, start a demo channel → the player shows the guard's message and the log has a refusal line and no request to the demo host; a Jellyfin item from `scripts/jellyfin-test-server.sh` plays under the same switches.
- [x] 3.2 Hold running streams (design 4): a live reconnect, continued download or keep-alive refused by the gate does not count as an attempt, waits for the gate, and reports `Health.waitingForVPN`. Add the debug MCP tool `set_vpn` (Mac tools and `FernsyTV/Debug/TVTools.swift`) and document it in DEVELOPMENT.md. Verify on the host against the demo server with `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=on`: play a demo channel, `set_vpn off` → the log shows the held reconnect and no request for 30 s, `set_vpn on` → "reconnected" and playback goes on; the same with the demo film (waits at its position, continues).
- [x] 3.3 Add unit tests in `FernsyPlayer` for the source's states with a faked gate: refused first connect, held reconnect that does not spend attempts, release on gate open, cancel while held. Verify they pass on the host (`scripts/test.sh`).

## 4. Artwork

- [x] 4.1 Check the gate in both image pipelines before a download, except for the signed-in Jellyfin server's and Fernsy Cloud's hosts; a blocked load returns nothing and is not remembered as failed. Verify against the demo server on the Apple TV simulator with `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=off` after one run with the VPN faked on: cached logos show, the log has no image request to the demo host, and after `set_vpn on` a newly shown logo loads.

## 5. Recordings

- [x] 5.1 Make `Recorder.begin` leave a planned recording untouched while the gate is closed, and give a recording that ends as missed for that reason the guard's message as its error text (design 5). Verify with `Recorder` unit tests using a faked gate: due while closed → still planned; gate opens before the end → started; never opens → missed with the reason.
- [x] 5.2 Verify a running recording on the host against the demo server (`IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=on`, `IPTV_MAXCONN=1`): record a demo channel, `set_vpn off` for 20 s, `set_vpn on` → the recording goes on to its end and its file plays with a gap, not as failed.

## 6. Mac app

- [x] 6.1 Add the setting to the IPTV account section of `Fernsy/Views/SettingsView.swift`: toggle "IPTV only with VPN", the line that says whether a VPN is seen (also while off), and a footer naming the limits (any VPN that carries the device's traffic counts; a VPN on the router or one that leaves Fernsy out is not seen). English and German in `Fernsy/Localizable.xcstrings`. Verify in Fernsy Dev in the VM: the status line follows `set_vpn on/off`, the toggle survives a relaunch, and `ICloudSync.syncedKeys` does not contain the key.
- [x] 6.2 Show the guard in the player's status card (`PlayerScreen.stallCard`: "VPN is not connected" / "Fernsy continues as soon as the VPN is back.") and as the reason when the app opens or reloads with the gate closed; run the refused sign-in or catalog load again when the gate opens (design 8). Verify in Fernsy Dev against the demo server: launch with `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=off` → cached channels with the VPN note and no request to the demo host in the log; `set_vpn on` → the catalog loads by itself.
- [x] 6.3 Verify the other entries to playback on the Mac under `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=off` against the demo server: the MCP tool `play` and the assistant answer with the guard's message, and a finished recording from the list plays.

## 7. Apple TV and iPhone/iPad

- [x] 7.1 Add the setting with its status line and footer to the account screens in `FernsyTV/Screens/SettingsScreen.swift` and `FernsyiOS/SettingsView.swift` (identifiers `settings.vpnGuard`, `settings.vpnStatus`), English and German in both catalogs. Verify with a UI test on each platform: the toggle exists and is off on a fresh install, switching it on keeps it after a relaunch, and the status text changes with `set_vpn`.
- [x] 7.2 Show the guard in `PlayerStatusLayer` and at launch, and reload when the gate opens: on the Apple TV the existing failure state with the guard's message, on iPhone/iPad the offline start (`signIn = .offline`, note names the VPN) and `retrySignIn`. Verify with a new `VPNGuardUITests` in `FernsyTVUITests` on the host against the demo server: launch with `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=off` → starting a channel shows the guard's message; `set_vpn on` → the channel plays; `set_vpn off` while playing → the VPN card shows and the log has no request; `set_vpn on` → it plays again without input.
- [x] 7.3 Verify the iPhone/iPad start with a UI test in `FernsyiOSUITests` (`scripts/ios-uitest.sh`, demo server): opened with `IPTV_TESTVPNGUARD=1 IPTV_TESTVPN=off` and a stored demo account → the tabs show with the VPN note; after `set_vpn on` the channel list loads without input.

## 8. Integration

- [x] 8.1 Run the whole suite once with the guard at its default: package tests in the VM (`scripts/vm.sh scripts/test.sh`), Apple TV and iOS UI tests, and `openspec validate --all --strict`. Verify everything passes and that no test other than the new ones had to set `IPTV_TESTVPN`.
- [ ] 8.2 Check a real VPN on real devices, which needs the user's VPN account: with the user's VPN app on the Mac and on the Apple TV (Release build), the settings say "connected" when it is and "not connected" when it is not, a channel plays with the VPN, shows the VPN card when the VPN is disconnected, and continues after reconnecting. Record the VPN app and the result under "Notes from implementing" in design.md.

## Workflow follow-up

- Archive the change on `change/vpn-guard` after the checks, then merge into `main` and push when the user agrees.
- The user-visible commit carries `Release-Note-de` / `Release-Note-en` trailers for the new setting.
