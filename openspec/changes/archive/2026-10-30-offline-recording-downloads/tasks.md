# Tasks

## 1. FernsyCore: download store

- [x] 1.1 `CloudDownloads` (design A, B, D):
  - index `downloads.json` and files in `Application Support/CloudDownloads/`, excluded from backup, protection `completeUntilFirstUserAuthentication`;
  - states waiting, downloading (progress), downloaded, failed;
  - one download at a time;
  - space check (size + 1 GB);
  - cancel removes partial data;
  - "Remove Download".

  Verify with `CloudDownloadsTests` against a stubbed transfer (a protocol in front of `URLSession`): enqueue two, the second waits; cancel cleans up; the space check refuses with needed/free bytes; the index survives a new instance; the backup exclusion flag is set.
- [x] 1.2 Background transfer: the `URLSession` with the identifier `de.mobilistics.fernsy.downloads`, the details GET first, then a `downloadTask` for the data. Resume data on interruption; on a 403 with resume data, fetch fresh URLs and start over. After the move, check the size and the `FCR1` header. Verify with tests of the delegate logic (finished file → downloaded; wrong size → failed; resume data stored and used; 403 → new URL), and with the live dev worker (`IPTV_CLOUD`, `IPTV_CLOUDTOKEN`, `IPTV_CLOUDKEY`, `FERNSY_CLOUD_FIXTURE_ID`): download the UI-test fixture, and the bytes equal the R2 object's ciphertext size.
- [x] 1.3 Deletion rule in `CloudModel` (design E): after a successful list load with `account.state == .active`, remove downloads whose id is missing; `delete(item)` removes the download; a failed load or a non-active state removes nothing. Verify with `CloudModelTests` and the stubbed server: deleted elsewhere → removed; state `ended` with an empty list → kept; network failure → kept; "Delete Fernsy Cloud Data" → all removed.

## 2. FernsyPlayer: playback from the file

- [x] 2.1 `CloudByteSource` with a file chunk provider (design C), sharing decryption, cache and the damaged handling. Verify with `CloudByteSourceTests`: reading and seeking across chunk boundaries from a file sealed by `CloudFileEncryptor` gives the plaintext; a flipped byte ends as damaged; no network is used, with a URLSession stub that fails every request.

## 3. iOS app

- [x] 3.1 Recordings tab (design D):
  - the tab shows with a subscription or downloads;
  - rows carry "Download", the progress with cancel, "Downloaded" with "Remove Download";
  - offline, only downloads show, under the note;
  - a download plays from the file with the resume key `cloud.<id>`.

  Add the strings in English and German. Verify with `FernsyiOSUITests/CloudRecordingsUITests` on "iPad Air 11-inch (M4)" (`IPTV_CLOUD`, `IPTV_CLOUDTOKEN`, `IPTV_CLOUDKEY`, `FERNSY_CLOUD_FIXTURE_ID`, `IPTV_SERVER` = demo server): download the fixture, play it and seek; "Remove Download" brings back "Download".
- [x] 3.2 Settings › Fernsy Cloud shows the space used by downloads. The app delegate forwards `handleEventsForBackgroundURLSession` to `CloudDownloads`. Verify the storage line in the UI test after 3.1's download, and that a debug run logs the background session's events when the download finishes with the app in the background (simulator: Home during the download, then reopen).
- [x] 3.3 A debug switch `IPTV_TESTOFFLINE=1` that makes the cloud client and the Xtream/Jellyfin requests fail as `notConnectedToInternet` and sets `isNetworkAvailable = false`, for the offline tests. Document it in DEVELOPMENT.md. Verify that a debug run with it shows no network requests in the log.

## 4. Opening without a connection

- [x] 4.1 `TVModel` (design F): a connection failure while restoring the stored account gives `signIn = .offline` and keeps the credentials; `RootView` shows the tabs; tabs without a cache show "No connection"; when the network returns, the sign-in runs again by itself. A rejected login stays `.failed`. Verify with a UI test using `IPTV_TESTOFFLINE=1` and an empty Caches folder (the debug switch `IPTV_FRESHCATALOG=1`, added here if missing): the tabs show, Recordings lists a download made before in the same simulator, and it plays.
- [x] 4.2 Verify "Password changed": a UI test with the demo server and a wrong stored password (`IPTV_PASS=wrong` restored from the keychain stand-in) still shows the sign-in error, not the offline tabs.
- [x] 4.3 Jellyfin-only accounts offline. Verify with a UI test that restores a stored Jellyfin session (the session stand-in used by the existing Jellyfin UI tests, no real server) under `IPTV_TESTOFFLINE=1`: the tabs show, the Jellyfin tab shows its cached lists and the note as ios-app already specifies, and Recordings lists the download. Use no Jellyfin server or container.

## 5. Verification

- [x] 5.1 Run `openspec validate --all --strict`, `scripts/test.sh` and the full iPad UI test run. All must pass.
- [x] 5.2 On "iPad von Patrick" with a Release build (`FERNSY_CLOUD = YES`, production worker), the user: *Done 2026-10-30 by the user on "iPad von Patrick".*
  - downloads a real recording;
  - locks the iPad until it is done;
  - switches on airplane mode;
  - closes and reopens Fernsy;
  - plays and seeks the download;
  - then deletes the recording on the Mac, goes online, and sees the download disappear.

## Workflow follow-up

- On `change/offline-recording-downloads`: archive, then merge into `main` and push, with the user's consent.
