import FernsyCore
import Foundation

/// Plays a past show from the provider's archive (catch-up): a non-live item whose timeline runs
/// over the show. The archive (`/timeshift/…`) starts on a whole minute and rarely allows byte
/// ranges, so every seek requests it again from the target's minute and skips the seconds into
/// it; the status layer shows the spinner meanwhile.
@MainActor
public final class ArchivePlayback {
    public let channelId: Int
    public let start: Date
    public let end: Date
    private let engine: PlayerEngine
    /// The archive's URL from a start for so many minutes (the app's client and server time zone).
    private let url: (_ from: Date, _ minutes: Int) -> URL?

    public init(channelId: Int, start: Date, end: Date, engine: PlayerEngine, url: @escaping (_ from: Date, _ minutes: Int) -> URL?) {
        self.channelId = channelId
        self.start = start
        self.end = end
        self.engine = engine
        self.url = url
    }

    public var duration: Double { end.timeIntervalSince(start) }

    /// Plays from `position` seconds into the show.
    public func play(at position: Double = 0) {
        let target = min(max(0, position), max(0, duration - 1))
        let from = Date(timeIntervalSince1970: ((start.timeIntervalSince1970 + target) / 60).rounded(.down) * 60)
        let offset = from.timeIntervalSince(start)
        // The rest of the show and 5 minutes for a late end.
        let minutes = Int(((duration - offset) / 60).rounded(.up)) + 5
        guard let url = url(from, minutes) else { return }
        AppLog.info(.player, "archive of channel \(channelId) from \(from.formatted(date: .abbreviated, time: .shortened)), \(minutes) min")
        var external = ExternalPlayback(timelineOffset: offset, duration: duration, methodLabel: String(localized: "Archive", bundle: .module))
        external.restartAt = { [weak self] target in self?.play(at: target) }
        engine.load(url: url, isLive: false, startAt: target - offset, external: external)
    }
}
