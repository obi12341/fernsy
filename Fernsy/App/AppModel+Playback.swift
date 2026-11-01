import FernsyCore
import FernsyPlayer
import Foundation

extension AppModel {
    /// Starts `item` on the player window's engine: live from the player's tuner, a recording from
    /// its file, a film or episode from its resume position, Jellyfin, Fernsy Cloud and catch-up
    /// through `PlaybackStart`. Returns the archive controller for a past show; `jellyfinStarted`
    /// gets a Jellyfin item's controller once its stream is resolved (and `isCurrent` still holds).
    func startPlayback(_ item: PlayItem, on engine: PlayerEngine, isCurrent: @escaping @MainActor () -> Bool,
                       jellyfinStarted: @escaping @MainActor (JellyfinPlayback) -> Void) -> ArchivePlayback? {
        engine.trackPreferences = trackPreferences(for: item)
        let start = item.resumeKey.map { resumePosition($0) } ?? 0
        switch item.kind {
        case .live where playerTuner != nil:
            engine.load(tuner: playerTuner!)
        case .jellyfin(let itemId, let startAt, _):
            PlaybackStart.jellyfin(itemId: itemId, store: jellyfin, engine: engine, startAt: startAt,
                                   stillWanted: isCurrent, started: jellyfinStarted)
        case .recording(let id):
            engine.load(file: item.url, isGrowing: { Recorder.isGrowing(id) }, startAt: start)
        case .cloud(let id):
            PlaybackStart.cloud(id: id, engine: engine, startAt: start, source: { try await self.cloudSource(id) }, stillWanted: isCurrent)
        case .archive(let channelId, let from, let end):
            return PlaybackStart.archive(channelId: channelId, start: from, end: end, client: client,
                                         timeZone: account?.serverTimeZone, engine: engine)
        default:
            engine.load(url: item.url, isLive: item.isLive, startAt: start)
        }
        return nil
    }
}
