# Proposal

## Why

Fernsy Cloud recordings on iPad and iPhone only stream, so they cannot be watched on a plane or
a train. Whether the app opens offline depends on chance:
- **Catalog cache present:** the app opens with the stored account and the cached channel list,
  but nothing in it plays.
- **Cache removed by iOS:** the app shows the welcome screen with an error.

Neither offers anything to watch without a connection.

## What Changes

- **Download.** On iPad and iPhone, a cloud recording SHALL offer "Download". The encrypted
  object is fetched in the background and continues while the app is suspended or closed. A
  progress bar shows on the row. The download can be cancelled and is refused when the device
  lacks space.
- **Offline playback.** A downloaded recording plays from the device with seeking and resume,
  also without network, an active subscription or a reachable server.
- **Downloads stay.** Once downloaded, a recording remains playable after the subscription
  ends and after the server's cleanup removes the cloud copy (user decision).
- **Deletions follow the cloud.** While the subscription is active, a download disappears when
  its cloud recording is deleted on any device, including "Delete Fernsy Cloud Data". The
  user can also remove a single download on the device. Storage used by downloads shows in
  Settings.
- **Opening without a connection.** With a stored IPTV or Jellyfin account, the app opens into
  its tabs even when the server is unreachable and the catalog cache is gone. It says that
  there is no connection. The Recordings tab is there whenever downloads exist.
- Out of scope:
  - downloads on the Apple TV, whose storage tvOS may clear, and on the Mac, which has the
    files;
  - downloading live TV, films, series or Jellyfin items;
  - automatic downloads of new recordings;
  - a server change: the existing signed read URL, valid for six hours, carries one download.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recording-cloud`: new requirements for downloading, offline playback, downloads after the
  subscription ends, and deletions. "Cloud recordings on every device" changes so that the
  Recordings section also shows when downloads exist without a subscription.
- `ios-app`:
  - "Storage on iPhone and iPad" changes: downloads are kept where iOS does not clear them.
  - New requirement "Opening without a connection".

## Impact

- **FernsyCore:**
  - new `CloudDownloads` store: index, files in Application Support excluded from backup,
    background `URLSession`;
  - `CloudModel`: merges downloads into the list and applies the deletion rule.
- **FernsyPlayer:** `CloudByteSource` gets a file-backed variant that reads the encrypted
  chunks from disk.
- **iOS app:**
  - the Recordings rows get download, progress and remove actions and an offline state;
  - Settings shows the storage used by downloads;
  - `RootView` and `TVModel` open into the tabs without a connection;
  - the app delegate hands background `URLSession` events to the store.
- **Strings:** new English and German strings in the TV/iOS catalog and the core catalog.
- **Unchanged:** the server, the stored format, the Mac and the Apple TV.
