# Design

## Context

See proposal.md for the motivation. What shapes the approach:

- FFmpeg is built with `--disable-network`. Everything Fernsy sends to the provider goes through
  three places: `XtreamClient` (one request function for sign-in, catalog and guide),
  `HTTPByteSource` (every stream: playback, the timeshift tuner, recordings, MCP frame grabs) and
  the two image pipelines (`Fernsy/Support/ImagePipeline.swift`, `FernsyTV/Support/ImagePipeline.swift`,
  the latter shared with iPhone/iPad). No `AVPlayer` and no system component fetches provider URLs;
  the Top Shelf extension shows image files the app wrote.
- `HTTPByteSource` also carries Jellyfin streams, and the image pipelines also load Jellyfin and
  Fernsy Cloud artwork. Whether a request is the provider's has to be decided by who creates it.
- The apps already know one "cannot reach anything" state: `isNetworkAvailable` from
  `NWPathMonitor`, the "No internet connection" card in `PlayerScreen` and `PlayerStatusLayer`,
  the offline start on iPhone/iPad (`TVModel.isConnectionFailure`, `signIn = .offline`), and the
  live reconnect loop in `HTTPByteSource`.
- `FernsyShared` is also compiled for the Linux server. The guard must not pull Apple-only APIs
  into it.
- Measured on the development Mac (2026-11-13), with Tailscale connected as a split tunnel:
  `CFNetworkCopySystemProxySettings` lists `utun18` under `__SCOPED__` and `NWPath.availableInterfaces`
  contains it, while `NWPath.usesInterfaceType(.other)` is false and internet traffic leaves
  through `en0`. A check that only asks "is there a tunnel interface" would be wrong here.

## Goals / Non-Goals

**Goals:**

- With the setting on, no new connection to the provider is opened unless the device's internet
  traffic leaves through a tunnel, decided at the moment the connection is made.
- One gate, checked in the three places above, so that a new provider request added later cannot
  bypass it by accident.
- Reuse the existing offline and reconnect behavior; the guard adds a reason and a "VPN is back"
  trigger, not a second set of flows.
- Testable without a VPN: the detection can be faked by a debug switch and flipped during a run.

**Non-Goals:**

- Proving that the tunnel is a privacy VPN, that it is a certain provider's, or where it ends.
- Protecting against a VPN app's own leaks, or against split tunnelling by app or by address that
  leaves Fernsy or the provider outside the tunnel.
- Any change to the server, the cloud worker, entitlements or targets.

## Decisions

### 1. A guard, not a VPN client inside Fernsy

Fernsy checks for a VPN that another app provides and holds provider requests back without one.
Estimated at 4–5 days including tests on all three platforms.

Alternatives considered:

- **Proton VPN's client code** (github.com/ProtonVPN/ios-mac-app, the original request). Rejected,
  for three independent reasons. The code is GPLv3; Fernsy is PolyForm Noncommercial and the
  project rules exclude GPL components. The public repository cannot be built: the tunnel is a
  binary `protun.xcframework`, `external/vpn-core-apple` and `external/apple-fusion` are private
  submodules, and URLs and keys come from a private credentials repository. And sign-in and the
  server list use Proton's own API, which is not offered to other apps.
- **An in-app WireGuard tunnel for Fernsy's own traffic** (wireguard-go with its userspace network
  stack, a SOCKS proxy on 127.0.0.1, provider sessions pointed at it through
  `URLSessionConfiguration.proxyConfigurations`; the user imports a WireGuard configuration, which
  Proton and others let them create). Not now: about 4–5 weeks. The Go library has to be built for
  tvOS, which the upstream build does not cover; configurations and private keys have to reach the
  Apple TV; and it is open whether App Review treats it as a VPN app under guideline 5.4, which
  requires the NEVPNManager API. It would give a true per-app tunnel with no second app. The gate
  of this change is the base it would build on: provider sessions would get the proxy and the gate
  would ask the tunnel instead of the system.
- **A system VPN from Fernsy** (Network Extension packet tunnel with WireGuardKit). Rejected:
  about 6–8 weeks, three extension targets with new entitlements, guideline 5.4 applies for
  certain, WireGuardKit declares macOS and iOS only, extensions on iOS and tvOS have a tight
  memory limit for a Go runtime, Network Extensions do not run in simulators, and the DMG variant
  would need a system extension instead of an app extension. It would also tunnel the whole
  device, which is more than was asked for.

### 2. Detection: ask the kernel which interface carries internet traffic

`VPNProbe` opens a UDP socket, connects it to a fixed public address (one IPv4, one IPv6 literal),
reads the local address with `getsockname`, and finds the interface that owns it with
`getifaddrs`. Connecting a UDP socket sends no packet; it is a routing lookup. A VPN counts as
connected when every address family that has a route leaves through a tunnel interface (name
starting with `utun`, `ipsec`, `ppp`, `tun` or `tap`), and at least one family has a route. The
lookup is injected, so the rule is unit-tested without a network.

The gate runs the probe at each check, so the answer is the kernel's at that moment.
`NWPathMonitor` (already running in both models) is used only as the signal that something
changed and the published state should be refreshed.

Alternatives considered:

- **`__SCOPED__` keys of the system proxy settings**, the usual recipe. Rejected: lists a tunnel
  that carries only its own network (measured, see Context).
- **`NWPath.usesInterfaceType(.other)` as the answer.** Rejected as the gate's source: it is a
  delivered notification, so a reconnect triggered by the broken socket can run before the path
  update arrives, and it gives one answer for the default path, not one per address family. It
  stays the change trigger.
- **`NEVPNManager`.** Rejected: it only shows VPN configurations the app itself installed.
- **Asking a "what is my IP" service.** Rejected: a request to a third party, needs a baseline
  to compare with, and proves nothing about the next connection.
- **Looking up the provider's own address instead of a fixed one.** Rejected: needs a DNS query
  for the provider's host before the check, and streams are redirected to hosts not known in
  advance.

### 3. One gate in `FernsyShared`, checked where connections are made

`ProviderGate` holds the setting (`UserDefaults`, key not in `ICloudSync.syncedKeys`) and the
probe, and offers `check()` (throws `ProviderGateError.vpnRequired`) and `isOpen`. On Linux it is
always open. It is checked

- in `XtreamClient`'s request function, before the request;
- in `HTTPByteSource`, before every task it starts (first connect, live reconnect, continued
  download, keep-alive), when the source was created as a provider source. `PlaybackSession` and
  the MCP frame source pass that flag: true for Xtream URLs, false for Jellyfin (`ExternalPlayback`)
  and never set for file and cloud sources;
- in both image pipelines, before a download, unless the URL's host is the signed-in Jellyfin
  server's or Fernsy Cloud's. A blocked load returns nothing and is not cached as a failure, so
  the image loads when the view asks again with the VPN up.

`ProviderGateError` counts as a connection failure for the existing offline handling
(`isConnectionFailure` and its Mac counterpart) and carries the localized message.

Alternatives considered:

- **A failing `URLProtocol` on the provider sessions**, as `TestOffline` does in debug builds.
  Rejected: it can only fail a request, and the stream source needs to know the difference between
  "refused by the guard" and "failed" to hold a reconnect (decision 4); the reason would also
  arrive as a generic loading error.
- **Deciding by URL** (`/live/`, `/movie/` … as `PlayerError.debugAllows` does). Rejected: a
  reconnect to the edge host a stream was redirected to does not have that shape.

### 4. A first connection is refused, a running stream is held

Starting something without a VPN fails at once with the guard's message, so the user sees why.
A stream that already ran is different: when a live reconnect or a continued download is refused
by the gate, `HTTPByteSource` does not count it as an attempt and does not give up. It waits and
asks the gate again when the state changes (and once a second as a fallback), until the gate opens
or the source is cancelled. Its health reports the new case `waitingForVPN`, which the two status
cards show as "VPN is not connected – Fernsy continues as soon as the VPN is back." This gives
live playback, films, timeshift and running recordings the same behavior with one mechanism, and
a recording ends at its planned end as before.

Alternative considered: fail the stream and let each caller retry when the VPN is back. Rejected:
four callers (player on three platforms, recorder) would each need a retry path, and the timeshift
buffer and the recording file would be closed and reopened.

### 5. Planned recordings stay planned

`Recorder.begin` returns without changing the recording while the gate is closed; the tick tries
again. At the show's end the existing rule marks it missed, now with the guard's reason as its
error text. Alternative considered: mark it failed at the start time like other refusals
(`recordingRefusal`). Rejected: the VPN often comes back within the show.

### 6. Artwork is held back too

Logos and posters come from wherever the provider's catalog points, often the provider's own
host. They are downloads "for IPTV content" and reveal the address as well. Third-party image
hosts cannot be told apart from the provider's, so all artwork except Jellyfin's and Fernsy
Cloud's is held. Cached images keep showing. Alternative considered: leave artwork alone to keep
lists pretty. Rejected: it would break the one promise the setting makes.

### 7. Per device, off by default, not synced

A device behind a VPN router cannot see that VPN and must keep the setting off, while the laptop
of the same user wants it on. Alternative considered: sync it like the other choices. Rejected for
that reason. The settings show the probe's answer also while the setting is off, so the user can
check that their VPN is recognized before switching it on.

### 8. When the VPN comes back

`ProviderGate` publishes changes of `isOpen`. `AppModel` and `TVModel` react to "open again" the
way they react to "network available": a sign-in or catalog load that the gate refused is run
again (on iPhone/iPad through the existing `retrySignIn`). Held streams continue by themselves
(decision 4).

### 9. Debug switches

- `IPTV_TESTVPN=on|off` (debug builds): replaces the probe's answer.
- `IPTV_TESTVPNGUARD=1` (debug builds): the setting is on for this run, without storing it.
- Debug MCP tool `set_vpn` (`on`/`off`): flips the faked answer during a run, like `set_offline`.
- The gate logs every change and every refusal (`AppLog`, category network), with the interface
  names the probe found, so tests can wait for the lines and a user's log shows why it blocked.

The demo account is a provider like any other for the gate, so all checks run against the demo
server.

## Risks / Trade-offs

- [The answer is "a tunnel carries internet traffic", not "a privacy VPN is on": a company VPN or
  a Tailscale exit node counts] → Stated in the setting's footer; checking the provider is a
  non-goal.
- [A VPN app that excludes Fernsy or the provider's addresses from the tunnel is not noticed] →
  Stated in the footer; a per-connection check (comparing a connection's local address from the
  task metrics with the tunnel's) could be added later without changing the gate.
- [A VPN that tunnels IPv4 only, on a network with IPv6, is reported as "no VPN"] → Intended, it
  is a real leak; the log line names the family so support can explain it.
- [Router VPNs are invisible] → The setting stays off on such devices (decision 7).
- [BSD sockets and `getifaddrs` behave differently in the sandbox or on tvOS] → Task group 1
  checks the probe on the Mac, in the VM with a full-tunnel route, and in the tvOS and iOS
  simulators before anything is built on it; if the lookup is not usable somewhere, the gate falls
  back to `NWPath.usesInterfaceType(.other)` on that platform and the design is updated.
- [An established connection moving to another interface when the tunnel goes away] → TCP
  connections cannot; Fernsy does not enable multipath, and provider streams are HTTP/1.1. Not
  handled further.
- [A probe at every check costs time] → Two socket calls without I/O; the image pipelines check
  once per download, which is far below the cost of the download itself.

## Open Questions

- Whether the README's feature list should mention the setting. It does not affect the build.

## Notes from implementing

- **Where the probe lives.** `VPNProbe` is in `FernsyShared` next to `ProviderGate`, not in
  `FernsyCore` as decision 2 says: the gate needs it and `XtreamClient` (FernsyShared) needs the
  gate. The real lookup is compiled only where Darwin is; on Linux it reports no route and the
  gate is open. `XtreamClient` carries its gate as a property (default `ProviderGate.shared`), so
  the tests give it their own instead of switching a global one.
- **The lookup, checked 2026-11-13 (task 1.2)** with a tool built from `VPNProbe.swift`:
  - Development Mac, Tailscale connected as a split tunnel: `no VPN (IPv4 en0, IPv6 en0)`.
  - Tart VM, no tunnel: `no VPN (IPv4 en0, IPv6 en0)`.
  - Tart VM, a `utun` holding `0.0.0.0/1` and `128.0.0.0/1` (as WireGuard sets a full tunnel)
    while the VM also has IPv6 through `en0`: `no VPN (IPv4 utun4, IPv6 en0)` – the "IPv6 beside
    the tunnel" rule on a real network.
  - The same with `::/1` and `8000::/1` added: `VPN (IPv4 utun4, IPv6 utun4)`; after removing the
    routes `no VPN (IPv4 en0, IPv6 en0)` again.
  - Inside the Apple TV and iPad simulators (`xcrun simctl spawn`, built for the simulator SDKs):
    the same three answers as the VM's Mac. The simulators use the Mac's network, so this shows
    that the calls work in those runtimes, not how a real Apple TV routes; that is task 8.2.
  - The routes take a few seconds to appear after the interface is configured; a check right
    after "connect" can still see the direct route.
- **A running stream is cut, not only kept from reconnecting.** With the faked answer the
  connection stays up when the "VPN" goes, and a real VPN could also change routes without
  breaking the socket. The source therefore asks the gate while it runs: live streams in their
  watchdog (every 0.5 s), film downloads when data arrives (at most once a second). A closed
  gate cancels the task and holds the next request. `read` does not time out while the source
  waits, and a seek in a film that already ran waits inside `connect(at:)`.
- **The film's last part is not cut.** A download that just received its last byte has nothing
  to continue; cutting it asked for a range past the end when the VPN came back (seen with the
  demo film, 2026-11-13).
- **Who knows that a stream is the provider's.** `PlaybackSession` takes `guarded` (default
  true); the engine passes `ExternalPlayback.contactsProvider`, which only `JellyfinPlayback`
  sets to false (archived shows use `ExternalPlayback` too and are the provider's). The engine
  publishes the same as `contactsProvider` for the status cards. The MCP frame source is used
  for Jellyfin only and gets no gate.
- **The status cards do not rely on the connection's health.** Only tuners report it to the
  engine; a channel without timeshift and a film do not. The cards show the VPN note when the
  item is the provider's and `VPNGuardState.isBlocking` (or the health says so).
- **`VPNGuardState`** (FernsyCore, main actor) is what views and models observe: it follows the
  gate's announcements, looks every 2 s while the setting is on or a settings page shows the
  status, and sends `reopened` when the provider can be reached again. The path monitors call
  its `update()` too; alone they were not relied on.
- **Refused in the tuner.** A refused first connection reaches `LiveTuner` as a failure that is
  not to be retried, which it otherwise takes for the provider's offline placeholder. The tuner
  recognizes the guard's message and neither marks the channel offline nor waits 30 s for a
  recording's next try (5 s).
- **Artwork.** The user's own host is the Jellyfin session's (`ProviderGate.setOwnHost`, set by
  `JellyfinStore`); Fernsy Cloud has no artwork of its own. The Apple TV's `ChannelLogo` loaded
  through `AsyncImage`, which neither the gate nor the disk cache reaches; it uses `RemoteImage`
  now, as the library's tiles do since tvos-library (design: "Rejected: AsyncImage"). The Mac's
  pipeline asks its `URLCache` only (`returnCacheDataDontLoad`) while the gate is closed.
- **Entries that would only open a failing player** (the MCP tool `play`, the assistant's
  `play`, Siri's "play channel") ask the gate first and answer with its message. Planning a
  recording through them is not refused: it waits like any planned recording.
- **No debug tool on the Mac.** The Mac app has no debug MCP tools; `IPTV_TESTVPN` takes timed
  steps instead (`on,20:off,50:on`). `set_vpn` exists on the Apple TV, iPhone and iPad.
- **Not unit-tested where the task said so.** `isConnectionFailure` lives in the app target, so
  its new case is covered by the iPhone UI test (opened without a VPN: tabs and the VPN note),
  not by a unit test.
- **A gap in a recording is logged with the provider as its cause** ("the provider delivered too
  little") also when the VPN was the reason; the text is the gap tracker's and was left as it is.
- **The lookup inside the sandbox.** Fernsy Dev (App Sandbox) on the development Mac with the
  real lookup (`IPTV_TESTVPNGUARD=1`, no `IPTV_TESTVPN`), Tailscale connected as a split tunnel:
  `vpn guard on: no VPN (IPv4 en0, IPv6 en0)`, and the provider requests are refused.
- **Checked on the Mac (Fernsy Dev, demo server, 2026-11-13).** Opened without a VPN: cached
  channels with the banner "No VPN Connection", ten refused requests, none sent; VPN on after
  25 s: "the VPN is connected, loading the catalog", refresh in 177 ms. A channel started
  without a VPN: refused, the player shows the guard's message, no connection. A channel that
  ran: VPN off at 20 s, the stream waited 35 s without a request, "reconnected" 0.3 s after the
  VPN was back. A film from a local server at 330 kB/s (`IPTV_PLAYURL`): the server saw its
  connection closed when the VPN went and the next request ("from byte 6303000") only after it
  was back; the card showed meanwhile and the film played to its end. A one-minute recording
  (`IPTV_TESTRECORD=104:5:60:0:0`, `IPTV_MAXCONN=1`) with the VPN off for 20 s: finished as
  done with one gap, and its file plays. The MCP tool `play` answers with the guard's message
  for a channel and a film and plays the test Jellyfin's film (`scripts/jellyfin-test-server.sh`).
  The stored setting is read at the next launch; without it no request is held.
- **Not checked by clicking on the Mac.** The Mac app has no UI tests and input is not injected:
  the toggle itself was exercised on the Apple TV and the iPhone (UI tests), which share
  `VPNGuardState`; on the Mac the stored value and the status line were checked.
- **Cached artwork.** The UI test shows that nothing is downloaded without a VPN and that
  artwork loads with it. That cached images keep showing follows from the order in the
  pipelines (memory and disk are read before the gate is asked) and was seen on the Mac
  (cached channel list); there is no test of its own for it.
- **The whole suite (task 8.1, 2026-11-13).** FernsyCore package tests in the VM: passed.
  FernsyPlayer package tests on the host: 34 passed. Apple TV UI tests on the host: 85 tests, 68
  passed, 17 skipped (they need the test Jellyfin or Fernsy Cloud), none failed. iPhone UI tests
  in the VM: the seven playback tests failed there as they always do (no hardware decoding in
  the VM); four of them passed on the host. `StartClockUITests.testLiveCardMovesOnToTheNextShow`
  failed in the whole run (the app opened in the tab the test before left selected) and passed
  alone; not compared with `main`. No test but the new ones sets `IPTV_TESTVPN`.
