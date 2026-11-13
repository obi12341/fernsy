# Proposal

## Why

Users who reach their IPTV provider only through a VPN have no protection in Fernsy today: when
the VPN app is not connected, or drops while a channel plays, Fernsy signs in, loads the catalog
and reconnects the stream over the bare internet connection. The request was to build Proton VPN's
open-source client into the apps; that is not possible (see design.md, decision 1), but the
guarantee behind it is: Fernsy contacts the provider only while the device's traffic runs through
a VPN.

## What Changes

- A new setting "IPTV only with VPN" in the Mac, iPhone/iPad and Apple TV apps, off by default and
  kept per device. Next to it the app says whether it currently sees a VPN.
- While the setting is on and the device's internet traffic does not leave through a VPN tunnel,
  Fernsy sends nothing to the IPTV provider: no sign-in, catalog or guide request, no live, film,
  episode or catch-up stream, no recording, and no artwork download for IPTV items.
- A stream that is running when the VPN drops stops receiving at once and is not reconnected; the
  player says that the VPN is not connected and continues by itself when it is back.
- Opening the app without a VPN behaves like opening it without a connection, with the VPN named
  as the reason; the catalog loads by itself once the VPN connects.
- A planned recording does not start without a VPN; it starts as soon as the VPN connects within
  its time.
- Jellyfin, Fernsy Cloud, a paired Fernsy Server, iCloud, updates and files on the device are not
  affected.

Out of scope:

- A VPN client inside Fernsy: Proton's code, an in-app WireGuard tunnel for Fernsy's own traffic,
  or a system VPN extension. They were assessed and are recorded in design.md.
- Choosing or checking a particular VPN provider, server or country. Any VPN that carries the
  device's internet traffic counts.
- VPNs the device cannot see (a VPN on the router), and VPN apps set to leave Fernsy or the
  provider out of the tunnel.
- The Fernsy Server (Docker) and the headless recorder: they run in their own network, which the
  user routes through a VPN there.
- Syncing the setting between devices, a setting per account, and protecting other apps.

## Capabilities

### New Capabilities

- `vpn-guard`: the optional rule that Fernsy contacts the IPTV provider only while the device's
  traffic runs through a VPN – the setting, what counts as a VPN, what is held back, and what the
  apps show and do when the VPN is missing or comes back.

### Modified Capabilities

None. The existing requirements for missing network, dropped connections and offline start keep
their behavior; the guard adds its own.

## Impact

- `Packages/FernsyCore` (`FernsyShared`, `FernsyCore`): the VPN check, the gate with its setting,
  the check in `XtreamClient`, new strings in the package's catalog.
- `Packages/FernsyPlayer`: `HTTPByteSource` (refuse or hold connections of provider streams),
  `PlaybackSession`/`LiveTuner` (mark provider streams), `Recorder` (planned recordings wait).
- `Fernsy`, `FernsyTV`, `FernsyiOS`: settings, the player's status card, reloading when the VPN
  connects, both image pipelines, string catalogs (English and German).
- Debug switches and tools: `IPTV_TESTVPN`, `IPTV_TESTVPNGUARD`, the debug MCP tool `set_vpn`;
  documented in DEVELOPMENT.md.
- No new dependency, entitlement or extension target; no change to the server, the cloud worker
  or the privacy policy (no new third-party connection).
