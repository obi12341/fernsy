import FernsyCore
import Foundation

/// Starting the kinds of playback the Mac and the Apple TV both start the same way
/// (code-structure-cleanup 3.4): a Jellyfin item resolves its stream first, a Fernsy Cloud
/// recording its download URL, and a past show plays from the channel's archive.
@MainActor
public enum PlaybackStart {
    /// Resolves the Jellyfin item's stream, then starts at `startAt`, unless the player moved on
    /// meanwhile (`stillWanted`). `started` gets the controller before it starts.
    public static func jellyfin(itemId: String, store: JellyfinStore, engine: PlayerEngine, startAt: Double,
                                stillWanted: @escaping @MainActor () -> Bool,
                                started: @escaping @MainActor (JellyfinPlayback) -> Void) {
        Task { @MainActor in
            guard let playback = await JellyfinPlayback.make(itemId: itemId, store: store, engine: engine), stillWanted() else { return }
            started(playback)
            playback.start(at: startAt)
        }
    }

    /// Opens the cloud recording's stream and plays it from `startAt`; a failure shows in the player.
    public static func cloud(id: String, engine: PlayerEngine, startAt: Double,
                             source: @escaping () async throws -> CloudByteSource,
                             stillWanted: @escaping @MainActor () -> Bool) {
        Task { @MainActor in
            do {
                let source = try await source()
                guard stillWanted() else { return }
                engine.load(cloud: source, startAt: startAt)
            } catch {
                AppLog.warning(.player, "Fernsy Cloud: cannot play \(id.prefix(8)): \(error)")
                engine.reportFailure(CloudModel.describe(error))
            }
        }
    }

    /// A past show from the channel's archive; every seek requests the archive again from there
    /// (catch-up design 3).
    public static func archive(channelId: Int, start: Date, end: Date, client: XtreamClient?, timeZone: TimeZone?,
                               engine: PlayerEngine) -> ArchivePlayback {
        let playback = ArchivePlayback(channelId: channelId, start: start, end: end, engine: engine) { from, minutes in
            client?.archiveURL(channel: channelId, start: from, minutes: minutes, timeZone: timeZone)
        }
        playback.play()
        return playback
    }
}

public extension CloudModel {
    /// The recording's stream from Fernsy Cloud, renewing its download URL when it expires.
    func streamSource(for item: CloudRecordingItem) async throws -> CloudByteSource {
        let (url, meta) = try await playback(for: item)
        let client = client, id = item.id
        return CloudByteSource(recordingId: id, plaintextSize: meta.plaintextBytes, fileKey: meta.key, dataURL: url) {
            try await client.readURLs(id: id).dataURL
        }
    }
}
