# Design

## Context

See proposal.md – Why. What exists now (recording-cloud, cloud-server, add-recording-cloud
design C):

- **The cloud object.** It is a 16-byte `FCR1` header followed by 1 MiB AES-GCM chunks under
  the recording's file key. The details object (`FCM1`) holds title, times and the file key,
  sealed with the account key, which sits in the keychain and in iCloud.
- **Streaming.** `CloudByteSource` (FernsyPlayer) fetches encrypted chunks with range requests
  on a signed read URL, decrypts them and feeds plaintext offsets to FFmpeg.
  `CloudModel.playback(for:)` asks the server for the URL (`readURLs`, valid six hours).
- **The iOS app.** It shares `TVModel` with the Apple TV. `TVModel.signIn(_:remember: false)`
  applies `CatalogCache` (in Caches) first, then calls `client.account()`. If the server fails:
  - with channels from the cache, the state becomes `.signedIn`;
  - without them, it becomes `.failed`, and `RootView` shows `WelcomeView`, unless a Jellyfin
    session exists.

  The Recordings tab appears only with `cloud.hasSubscription`, and its list comes only from
  the server.
- **Network state.** `TVModel.isNetworkAvailable` comes from an `NWPathMonitor`. Today only the
  player's stall card reads it.

User decisions (2026-10-30):
- Downloads stay after the subscription ends.
- A deletion in the cloud removes the download too.

## Goals / Non-Goals

**Goals:**
- Download in the background, with the app suspended or closed.
- Offline playback with instant seeking.
- The app opens into its tabs without a connection.

**Non-Goals:**
- Downloads on the Apple TV or the Mac, and downloads of anything other than cloud recordings.
- Partial downloads that play while they load. Streaming covers that case.
- Keeping downloads across a device restore. They are excluded from backups.

## Decisions

### A. Store the object as it is in the cloud

A download is the exact `FCR1` data object plus the sealed `FCM1` details object. They are
saved under `Application Support/CloudDownloads/<id>.data` and `<id>.meta`. Both files are
marked `isExcludedFromBackup` and use the file protection
`completeUntilFirstUserAuthentication`, so a background download can write while the iPad is
locked. An index `downloads.json` holds, for each download, the id, the state, the expected
size, the time it was completed, and the resume data when interrupted.

Because the files stay encrypted, a copied file reveals nothing (the "Stays encrypted"
scenario). The per-chunk authentication works as when streaming, so a damaged file shows as
damaged instead of feeding garbage to the demuxer.

Rejected:
- **Decrypting to a plain `.ts` file and playing it with `FileByteSource`:** simpler playback,
  but the device would hold readable video and details outside the app's control, contrary to
  "end-to-end encrypted, decrypted only while it plays".
- **Caches:** iOS empties them under pressure, so a download for a flight could vanish.
  ios-app "Storage" now names downloads as the exception.

### B. One background `URLSession` download per recording

`CloudDownloads` owns a background `URLSession` (identifier
`de.mobilistics.fernsy.downloads`). A download proceeds in three steps:
1. fetch the read URLs (`readURLs`, which the server also uses for streaming);
2. GET the details object directly, since it is small;
3. start one `downloadTask` for the data object.

When the task finishes, the temporary file is moved to `<id>.data`. The app then checks its
size against `CloudFileLayout(plaintextSize:).ciphertextSize` and the `FCR1` header. The app
delegate passes `handleEventsForBackgroundURLSession` to the store, so it can finish while the
app is closed.

**Interruptions:** on a lost connection the task's `resumeData` is saved. The download goes on
with it when the network returns or the app opens. The signed URL lasts six hours, and S3
checks it only when a request starts. If a resume after more than six hours fails with 403,
the app fetches a fresh URL and starts that download over. This is rare enough to accept.

**Space:** a download is refused unless the free space (`volumeAvailableCapacityForImportantUsage`)
exceeds the object's size plus 1 GB.

**Concurrency:** one download runs at a time; others wait in the index in order. This keeps the
background session predictable and the progress honest.

Rejected:
- **Range requests in 64 MiB parts from the foreground (like the upload):** they stop when iOS
  suspends the app, so the iPad would have to stay open. Background tasks for every part would
  run into iOS's rate limit for tasks created in the background, and their URLs would expire
  while they wait.
- **A longer-lived URL from the server:** six hours carries a 7 GB download down to about
  3 Mbit/s. A server change is not worth it for the rare slower case.

### C. Playback from the file

`CloudByteSource` gets a second chunk provider: a `FileHandle` on `<id>.data` in place of HTTP
range requests. Decryption, the chunk cache and the `damaged` handling stay shared. The player
loads it through the existing `PlayerEngine.load(cloud:)`. The resume key stays
`cloud.<id>`, so position and watched state are the same whether the recording streams or
plays from the file.

The details come from `<id>.meta`, opened with the account key from the keychain
(`CloudKeyStore.loadLocal`, no network). A downloaded recording therefore always plays from the
file, even online, which saves data and starts faster.

### D. The list: cloud merged with downloads

`CloudModel.items` stays the server's list. A new `CloudDownloads.items` lists the completed
downloads with their details read from `.meta`. Recordings on iOS shows the union by id, as
follows:
- **Online:** a cloud item carries its download state: none, waiting, a percentage, or
  downloaded.
- **Offline or server unreachable:** only downloads are shown, under the note "Offline – only
  downloaded recordings".
- **Tab visibility:** the Recordings tab shows when `hasSubscription || !downloads.isEmpty`.

### E. Deletion rule

After every successful cloud list load, the app removes each download whose id is missing from
the list, but only when `account.state == .active`. The cases:
- **Deleted on the Mac:** removed.
- **"Delete Fernsy Cloud Data" with an active subscription:** removed.
- **Subscription ended, or the server's cleanup after the grace period:** the state is not
  active, so the downloads stay. That is the user's "stay forever".
- **A failed load:** never removes anything.

The deletion of a cloud recording on the iPad itself (`cloud.delete`) also removes its download
right away.

Rejected:
- **Removing downloads whenever the list misses them:** this would delete them after the grace
  period, against the user's decision.

### F. Opening without a connection

In `TVModel.signIn(remember: false)`, an error that is a connection failure (`URLError` with
code `notConnectedToInternet`, `networkConnectionLost`, `timedOut`, `cannotFindHost` or
`cannotConnectToHost`, or the path monitor saying no network) works like this:
- **State:** `signIn` becomes `.offline` (new case), not `.failed`. `credentials` and the
  client are kept. `recorder` is not involved: the iOS app does not record.
- **Main UI:** `RootView` shows `MainTabView` for `.offline`, as for `.signedIn`. The tabs
  without a cache show an empty state with the note "No connection".
- **Recovery:** when `isNetworkAvailable` turns true while `.offline`, `signIn(remember:
  false)` runs again.
- **Other errors:** a rejected login and other server errors keep `.failed` as today (the
  "Password changed" scenario). Without a cache that shows the welcome screen, as before; the
  restore path has never shown the error text there (found in task 4.2).

The Jellyfin path already keeps its stored session, so it needs no change, which is checked in
task 4.3.

Rejected:
- **Showing only the Recordings tab while offline:** the cached guide, favourites and Jellyfin
  lists are useful offline too, and switching layouts on a flaky connection would be jarring.

## Risks / Trade-offs

- **[The account key is lost (iCloud reset) after the subscription ended]** → the `.meta`
  cannot be opened, so the download cannot play. That matches the cloud copy, whose key is
  gone too. The row shows "Locked" as cloud rows do and offers "Remove Download".
- **[Large downloads fill the iPad]** → the space check plus the margin, the storage line in
  Settings, and "Remove Download".
- **[Background sessions are throttled on low battery or cellular]** → the session uses
  `isDiscretionary = false` and `allowsCellularAccess = true`, because the user started it on
  purpose. iOS can still delay it, and the row shows "Waiting".
- **[Downloads stay for a user who cancels after downloading]** → accepted by the user's
  decision. Downloads are per device and need the original Apple ID's key.

## Migration Plan

None. New files only. Nothing changes on the server or in the stored cloud format.

## As built

- **Tests.** `IPTV_TESTOFFLINE=1` adds a failing `URLProtocol` to the Xtream and Jellyfin
  sessions and registers it for `URLSession.shared` (Fernsy Cloud, cloud details). The debug
  MCP server on 127.0.0.1 stays reachable, and the MCP tool `set_offline` ends it during a run.
  `IPTV_FRESHCATALOG=1` empties Caches at launch. The Jellyfin-only case uses `JF_CACHEONLY` as
  the stored session, with no server involved.
- **The background.** In the simulator, a download that ran while the app was in the
  background finished there: the "downloaded" line came 75 s before the app was reactivated.
  iOS did not need to relaunch the app for this, so `handleEventsForBackgroundURLSession`
  (which only matters after iOS ended the app) is wired up but was not exercised. Task 5.2
  covers it on the iPad.
- **Space.** iOS uses `volumeAvailableCapacityForImportantUsage`. The Mac and tvOS, which do
  not offer downloads, use `volumeAvailableCapacity`.
- **The tab's offline line.** It shows when `signIn == .offline` or the path monitor reports no
  network. With a connection but an unreachable cloud server, the list shows the downloads
  next to the cloud's error message.
